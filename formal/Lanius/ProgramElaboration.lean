import Lean.Elab.Tactic.Omega
import Lanius.Declarations
import Lanius.Execution
import Lanius.Layout
import Lanius.Semantics
import Lanius.SurfaceElaboration
import Lanius.SourceWellFormed

namespace Lanius.ProgramElaboration

open Lanius

def genericParameterName : Surface.GenericParameter → Surface.Name
  | .type parameter => parameter.name
  | .const parameter => parameter.name

def GenericParameterNamesUnique (parameters : List Surface.GenericParameter) : Prop :=
  parameters.Pairwise fun left right => genericParameterName left ≠ genericParameterName right

def GenericParametersAreTypes : List Surface.GenericParameter → Prop
  | [] => True
  | .type _ :: tail => GenericParametersAreTypes tail
  | .const _ :: _ => False

/-- Type and const parameter IDs occupy separate dense domains, matching their
    distinct substitution maps. The source order is preserved in the combined
    alias-parameter list. -/
inductive GenericParametersLower
    (context : SurfaceElaboration.Context) :
    TypeParameterId → ConstParameterId → List Surface.GenericParameter →
      List SurfaceElaboration.TypeAliasParameter →
      TypeParameterId → ConstParameterId → Prop where
  | nil : GenericParametersLower context nextType nextConst [] [] nextType nextConst
  | typeParameter
      (tail : GenericParametersLower context (nextType + 1) nextConst
        surfaceTail loweredTail finalType finalConst) :
      GenericParametersLower context nextType nextConst
        (.type parameter :: surfaceTail)
        (.typeParameter parameter.name nextType :: loweredTail)
        finalType finalConst
  | constParameter
      (usize : SurfaceElaboration.TypeGrounds context parameter.type
        (.scalar (.unsigned .usize)))
      (tail : GenericParametersLower context nextType (nextConst + 1)
        surfaceTail loweredTail finalType finalConst) :
      GenericParametersLower context nextType nextConst
        (.const parameter :: surfaceTail)
        (.constParameter parameter.name nextConst :: loweredTail)
        finalType finalConst

def aliasParameterToStatic :
    SurfaceElaboration.TypeAliasParameter → Static.GenericParameter
  | .typeParameter _ parameter => .typeParameter parameter
  | .constParameter _ parameter => .constParameter parameter

def aliasTypeBindings
    (parameters : List SurfaceElaboration.TypeAliasParameter) :
    List SurfaceElaboration.TypeParameterBinding :=
  parameters.filterMap fun
    | .typeParameter name parameter => some { name, parameter }
    | .constParameter _ _ => none

def aliasConstBindings
    (parameters : List SurfaceElaboration.TypeAliasParameter) :
    List SurfaceElaboration.ConstParameterBinding :=
  parameters.filterMap fun
    | .typeParameter _ _ => none
    | .constParameter name parameter => some { name, parameter }

theorem aliasTypeBindings_parameter_member
    (member : binding ∈ aliasTypeBindings parameters) :
    .typeParameter binding.parameter ∈ parameters.map aliasParameterToStatic := by
  induction parameters with
  | nil => simp [aliasTypeBindings] at member
  | cons head tail induction =>
      cases head with
      | typeParameter name parameter =>
          change binding ∈ ({ name, parameter } :: aliasTypeBindings tail) at member
          change .typeParameter binding.parameter ∈
            (.typeParameter parameter :: tail.map aliasParameterToStatic)
          simp only [List.mem_cons] at member ⊢
          rcases member with rfl | inTail
          · exact Or.inl rfl
          · exact Or.inr (induction inTail)
      | constParameter name parameter =>
          change binding ∈ aliasTypeBindings tail at member
          change .typeParameter binding.parameter ∈
            (.constParameter parameter :: tail.map aliasParameterToStatic)
          exact List.mem_cons.mpr (Or.inr (induction member))

theorem aliasConstBindings_parameter_member
    (member : binding ∈ aliasConstBindings parameters) :
    .constParameter binding.parameter ∈ parameters.map aliasParameterToStatic := by
  induction parameters with
  | nil => simp [aliasConstBindings] at member
  | cons head tail induction =>
      cases head with
      | typeParameter name parameter =>
          change binding ∈ aliasConstBindings tail at member
          change .constParameter binding.parameter ∈
            (.typeParameter parameter :: tail.map aliasParameterToStatic)
          exact List.mem_cons.mpr (Or.inr (induction member))
      | constParameter name parameter =>
          change binding ∈ ({ name, parameter } :: aliasConstBindings tail) at member
          change .constParameter binding.parameter ∈
            (.constParameter parameter :: tail.map aliasParameterToStatic)
          simp only [List.mem_cons] at member ⊢
          rcases member with rfl | inTail
          · exact Or.inl rfl
          · exact Or.inr (induction inTail)

def withGenericParameters
    (context : SurfaceElaboration.Context)
    (parameters : List SurfaceElaboration.TypeAliasParameter) :
    SurfaceElaboration.Context := {
  context with
  typeParameters := aliasTypeBindings parameters
  constParameters := aliasConstBindings parameters
}

def withSubstitution
    (context : SurfaceElaboration.Context)
    (substitution : Static.Substitution) : SurfaceElaboration.Context :=
  { context with substitution }

mutual
  /-- Symbolic type lowering retains generic parameters for schemes. Type
      aliases are expanded by their dedicated relation before entering a
      scheme; nominal struct/enum arguments remain symbolic. -/
  inductive TypeRetains (context : SurfaceElaboration.Context) :
      Surface.TypeExpr → Static.Ty → Prop where
    | builtin
        (single : SurfaceElaboration.singleNamePath? { segments } = some name)
        (found : Elaboration.builtinScalar? name = some scalar) :
        TypeRetains context (.path segments) (.scalar scalar)
    | parameter
        (single : SurfaceElaboration.singleNamePath? { segments } = some name)
        (notBuiltin : Elaboration.builtinTypePath? { segments } = none)
        (resolved : SurfaceElaboration.ResolvesTypeParameter
          context.typeParameters name binding) :
        TypeRetains context (.path segments) (.parameter binding.parameter)
    | nominal
        (symbol : Names.Symbol)
        (notBuiltin : Elaboration.builtinTypePath? { segments } = none)
        (notShadowed : SurfaceElaboration.GlobalTypePathNotShadowed
          context { segments })
        (resolved : SurfaceElaboration.ResolvesGlobal context .type { segments } symbol)
        (member : scheme ∈ context.nominalSchemes)
        (declaration : scheme.declaration = symbol.declaration)
        (argumentsFound : SurfaceElaboration.pathTypeArguments? { segments } =
          some surfaceArguments)
        (arguments : NominalArgumentsRetain context scheme.genericParameters
          surfaceArguments retainedTypeArguments retainedConstArguments) :
        TypeRetains context (.path segments)
          (.nominal scheme.type retainedTypeArguments retainedConstArguments)
    | array
        (element : TypeRetains context surfaceElement retainedElement)
        (length : ArrayLengthRetains context surfaceLength retainedLength) :
        TypeRetains context (.array surfaceElement surfaceLength)
          (.array retainedElement retainedLength)
    | slice (element : TypeRetains context surfaceElement retainedElement) :
        TypeRetains context (.slice surfaceElement) (.slice retainedElement)
    | reference (referent : TypeRetains context surfaceReferent retainedReferent) :
        TypeRetains context (.reference surfaceReferent) (.reference retainedReferent)

  inductive TypesRetain (context : SurfaceElaboration.Context) :
      List Surface.TypeExpr → List Static.Ty → Prop where
    | nil : TypesRetain context [] []
    | cons
        (head : TypeRetains context surfaceHead retainedHead)
        (tail : TypesRetain context surfaceTail retainedTail) :
        TypesRetain context (surfaceHead :: surfaceTail)
          (retainedHead :: retainedTail)

  inductive ArrayLengthRetains (context : SurfaceElaboration.Context) :
      Surface.ArrayLength → Static.Const → Prop where
    | literal : ArrayLengthRetains context (.literal value) (.literal value)
    | parameter
        (resolved : SurfaceElaboration.ResolvesConstParameter
          context.constParameters name binding) :
        ArrayLengthRetains context (.parameter name) (.parameter binding.parameter)

  inductive ConstTypeArgumentRetains (context : SurfaceElaboration.Context) :
      Surface.TypeExpr → Static.Const → Prop where
    | parameter
        (single : SurfaceElaboration.singleNamePath? { segments } = some name)
        (resolved : SurfaceElaboration.ResolvesConstParameter
          context.constParameters name binding) :
        ConstTypeArgumentRetains context (.path segments) (.parameter binding.parameter)

  inductive NominalArgumentsRetain (context : SurfaceElaboration.Context) :
      List Static.GenericParameter → List Surface.TypeExpr →
        List Static.Ty → List Static.Const → Prop where
    | nil : NominalArgumentsRetain context [] [] [] []
    | typeParameter
        (argument : TypeRetains context surfaceArgument retainedArgument)
        (tail : NominalArgumentsRetain context parameters surfaceArguments
          retainedArguments retainedConstants) :
        NominalArgumentsRetain context
          (.typeParameter parameter :: parameters)
          (surfaceArgument :: surfaceArguments)
          (retainedArgument :: retainedArguments) retainedConstants
    | constParameter
        (argument : ConstTypeArgumentRetains context surfaceArgument retainedArgument)
        (tail : NominalArgumentsRetain context parameters surfaceArguments
          retainedArguments retainedConstants) :
        NominalArgumentsRetain context
          (.constParameter parameter :: parameters)
          (surfaceArgument :: surfaceArguments)
          retainedArguments (retainedArgument :: retainedConstants)
end

/-- A declaration-retained type observes a symbolic substitution only at the
    generic parameters declared by that source item. Agreement on that domain
    is sufficient; substitutions may differ everywhere else. -/
theorem TypeRetains.substitute_eq_of_parameter_agreement
    (typeAgreement : ∀ parameter,
      .typeParameter parameter ∈
          declaredParameters.map aliasParameterToStatic →
        leftSubstitution.types parameter = rightSubstitution.types parameter)
    (constAgreement : ∀ parameter,
      .constParameter parameter ∈
          declaredParameters.map aliasParameterToStatic →
        leftSubstitution.constants parameter =
          rightSubstitution.constants parameter)
    (retained : TypeRetains
      (withGenericParameters baseContext declaredParameters)
      surfaceType retainedType) :
    retainedType.substitute leftSubstitution =
      retainedType.substitute rightSubstitution := by
  apply TypeRetains.rec
    (motive_1 := fun _ retained _ =>
      retained.substitute leftSubstitution =
        retained.substitute rightSubstitution)
    (motive_2 := fun _ retained _ =>
      Static.substituteTypes leftSubstitution retained =
        Static.substituteTypes rightSubstitution retained)
    (motive_3 := fun _ retained _ =>
      retained.substitute leftSubstitution =
        retained.substitute rightSubstitution)
    (motive_4 := fun _ retained _ =>
      retained.substitute leftSubstitution =
        retained.substitute rightSubstitution)
    (motive_5 := fun _ _ retainedTypes retainedConstants _ =>
      Static.substituteTypes leftSubstitution retainedTypes =
          Static.substituteTypes rightSubstitution retainedTypes ∧
        Static.substituteConstants leftSubstitution retainedConstants =
          Static.substituteConstants rightSubstitution retainedConstants)
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ retained
  · intro segments name scalar single found
    rfl
  · intro segments name binding single notBuiltin resolved
    have bindingMember : binding ∈ aliasTypeBindings declaredParameters := by
      simpa [withGenericParameters] using resolved.member
    have parameterMember :=
      aliasTypeBindings_parameter_member bindingMember
    have agreement := typeAgreement binding.parameter parameterMember
    simp [Static.Ty.substitute, agreement]
  · intro segments scheme surfaceArguments retainedTypes retainedConstants
      symbol notBuiltin notShadowed resolved member declaration argumentsFound
      arguments argumentsIH
    simp [Static.Ty.substitute, argumentsIH.1, argumentsIH.2]
  · intro surfaceElement retainedElement surfaceLength retainedLength element
      length elementIH lengthIH
    simp [Static.Ty.substitute, elementIH, lengthIH]
  · intro surfaceElement retainedElement element elementIH
    simp [Static.Ty.substitute, elementIH]
  · intro surfaceReferent retainedReferent referent referentIH
    simp [Static.Ty.substitute, referentIH]
  · rfl
  · intro surfaceHead retainedHead surfaceTail retainedTail head tail headIH tailIH
    simp [Static.substituteTypes, headIH, tailIH]
  · intro value
    rfl
  · intro name binding resolved
    have bindingMember : binding ∈ aliasConstBindings declaredParameters := by
      simpa [withGenericParameters] using resolved.member
    have parameterMember :=
      aliasConstBindings_parameter_member bindingMember
    have agreement := constAgreement binding.parameter parameterMember
    simp [Static.Const.substitute, agreement]
  · intro segments name binding single resolved
    have bindingMember : binding ∈ aliasConstBindings declaredParameters := by
      simpa [withGenericParameters] using resolved.member
    have parameterMember :=
      aliasConstBindings_parameter_member bindingMember
    have agreement := constAgreement binding.parameter parameterMember
    simp [Static.Const.substitute, agreement]
  · exact ⟨rfl, rfl⟩
  · intro surfaceArgument retainedArgument parameters surfaceArguments
      retainedArguments retainedConstants parameter argument tail argumentIH tailIH
    exact ⟨by
      simp [Static.substituteTypes, argumentIH, tailIH.1], tailIH.2⟩
  · intro surfaceArgument retainedArgument parameters surfaceArguments
      retainedArguments retainedConstants parameter argument tail argumentIH tailIH
    exact ⟨tailIH.1, by
      simp [Static.substituteConstants, argumentIH, tailIH.2]⟩

/-- Equal ordered arguments imply agreement on the retained declaration's
    parameter domain. -/
theorem TypeRetains.substitute_eq_of_arguments
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (retained : TypeRetains
      (withGenericParameters baseContext declaredParameters)
      surfaceType retainedType) :
    retainedType.substitute leftSubstitution =
      retainedType.substitute rightSubstitution := by
  exact retained.substitute_eq_of_parameter_agreement
    (fun _ member => leftBound.type_agrees rightBound member)
    (fun _ member => leftBound.const_agrees rightBound member)

theorem TypesRetain.substitute_eq_of_arguments
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (retained : TypesRetain
      (withGenericParameters baseContext declaredParameters)
      surfaceTypes retainedTypes) :
    Static.substituteTypes leftSubstitution retainedTypes =
      Static.substituteTypes rightSubstitution retainedTypes := by
  cases retained with
  | nil => rfl
  | cons head tail =>
      simp [Static.substituteTypes,
        head.substitute_eq_of_arguments leftBound rightBound,
        substitute_eq_of_arguments leftBound rightBound tail]

def SelectsTrait
    (context : SurfaceElaboration.Context) (path : Surface.Path)
    (selected : Static.TraitScheme) : Prop :=
  ∃ symbol,
    SurfaceElaboration.ResolvesGlobal context .type path symbol ∧
    selected ∈ context.traits ∧ selected.declaration = symbol.declaration ∧
    ∀ candidate,
      candidate ∈ context.traits → candidate.declaration = symbol.declaration →
      candidate.trait = selected.trait

inductive TraitBoundRetains (context : SurfaceElaboration.Context) :
    Static.Ty → Surface.TypeExpr → Static.TraitPattern → Prop where
  | path
      (selected : SelectsTrait context { segments } trait)
      (argumentsFound : SurfaceElaboration.pathTypeArguments? { segments } =
        some surfaceArguments)
      (arguments : TypesRetain context surfaceArguments retainedArguments) :
      TraitBoundRetains context receiver (.path segments) {
        trait := trait.trait
        receiver
        arguments := retainedArguments
      }
  | reference
      (bound : TraitBoundRetains context (.reference receiver)
        surfaceBound retained) :
      TraitBoundRetains context receiver (.reference surfaceBound) retained

inductive TraitBoundsRetain (context : SurfaceElaboration.Context)
    (receiver : Static.Ty) :
    List Surface.TypeExpr → List Static.TraitPattern → Prop where
  | nil : TraitBoundsRetain context receiver [] []
  | cons
      (head : TraitBoundRetains context receiver surfaceHead retainedHead)
      (tail : TraitBoundsRetain context receiver surfaceTail retainedTail) :
      TraitBoundsRetain context receiver (surfaceHead :: surfaceTail)
        (retainedHead :: retainedTail)

inductive GenericBoundsRetain (context : SurfaceElaboration.Context) :
    List Surface.GenericParameter → List Static.TraitPattern → Prop where
  | nil : GenericBoundsRetain context [] []
  | typeParameter
      (resolved : SurfaceElaboration.ResolvesTypeParameter
        context.typeParameters parameter.name binding)
      (bounds : TraitBoundsRetain context (.parameter binding.parameter)
        parameter.bounds retainedBounds)
      (tail : GenericBoundsRetain context surfaceTail retainedTail) :
      GenericBoundsRetain context (.type parameter :: surfaceTail)
        (retainedBounds ++ retainedTail)
  | constParameter
      (tail : GenericBoundsRetain context surfaceTail retainedTail) :
      GenericBoundsRetain context (.const parameter :: surfaceTail) retainedTail

inductive WherePredicatesRetain (context : SurfaceElaboration.Context) :
    List Surface.WherePredicate → List Static.TraitPattern → Prop where
  | nil : WherePredicatesRetain context [] []
  | cons
      (resolved : SurfaceElaboration.ResolvesTypeParameter
        context.typeParameters predicate.parameter binding)
      (bounds : TraitBoundsRetain context (.parameter binding.parameter)
        predicate.bounds retainedBounds)
      (tail : WherePredicatesRetain context surfaceTail retainedTail) :
      WherePredicatesRetain context (predicate :: surfaceTail)
        (retainedBounds ++ retainedTail)

inductive ParameterTypesRetain (context : SurfaceElaboration.Context) :
    List Surface.Parameter → List Static.Ty → Prop where
  | nil : ParameterTypesRetain context [] []
  | named
      (type : TypeRetains context surfaceType retainedType)
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      ParameterTypesRetain context (.named name surfaceType :: surfaceTail)
        (retainedType :: retainedTail)

inductive ReturnTypeRetains (context : SurfaceElaboration.Context)
    (functionName : Surface.Name) : Option Surface.TypeExpr → Static.Ty → Prop where
  | mainDefault (main : functionName = "main") :
      ReturnTypeRetains context functionName none (.scalar (.signed .i32))
  | unitDefault (notMain : functionName ≠ "main") :
      ReturnTypeRetains context functionName none .unit
  | value (type : TypeRetains context surfaceType retainedType) :
      ReturnTypeRetains context functionName (some surfaceType) retainedType

inductive ReturnTypeGrounds (context : SurfaceElaboration.Context)
    (functionName : Surface.Name) : Option Surface.TypeExpr → Static.GroundTy → Prop where
  | mainDefault (main : functionName = "main") :
      ReturnTypeGrounds context functionName none (.scalar (.signed .i32))
  | unitDefault (notMain : functionName ≠ "main") :
      ReturnTypeGrounds context functionName none .unit
  | value (lowered : SurfaceElaboration.TypeGrounds context surfaceType groundType) :
      ReturnTypeGrounds context functionName (some surfaceType) groundType

theorem omitted_return_type_retains_unique
    (left : ReturnTypeRetains context functionName none leftType)
    (right : ReturnTypeRetains context functionName none rightType) :
    leftType = rightType := by
  cases left <;> cases right <;> simp_all

theorem omitted_return_type_grounds_unique
    (left : ReturnTypeGrounds context functionName none leftType)
    (right : ReturnTypeGrounds context functionName none rightType) :
    leftType = rightType := by
  cases left <;> cases right <;> simp_all

/-- Retained function parameter types observe only the owning declaration's
    ordered generic arguments. -/
theorem ParameterTypesRetain.substitute_eq_of_arguments
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (retained : ParameterTypesRetain
      (withGenericParameters baseContext declaredParameters)
      surfaceParameters retainedTypes) :
    Static.substituteTypes leftSubstitution retainedTypes =
      Static.substituteTypes rightSubstitution retainedTypes := by
  induction retained with
  | nil => rfl
  | named head tail induction =>
      simp [Static.substituteTypes,
        head.substitute_eq_of_arguments leftBound rightBound,
        induction]

/-- The retained return type has the same declaration-domain dependency. -/
theorem ReturnTypeRetains.substitute_eq_of_arguments
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (retained : ReturnTypeRetains
      (withGenericParameters baseContext declaredParameters)
      functionName surfaceReturn retainedType) :
    retainedType.substitute leftSubstitution =
      retainedType.substitute rightSubstitution := by
  cases retained with
  | mainDefault => rfl
  | unitDefault => rfl
  | value type => exact type.substitute_eq_of_arguments leftBound rightBound

structure SymbolicLocalBinding where
  name : Surface.Name
  type : Static.Ty

structure SymbolicBodyContext where
  globals : SurfaceElaboration.Context
  assumptions : List Static.TraitPattern := []
  returnType : Static.Ty := .unit
  locals : List SymbolicLocalBinding := []

def SymbolicBodyContext.bind
    (context : SymbolicBodyContext) (name : Surface.Name)
    (type : Static.Ty) : SymbolicBodyContext :=
  { context with locals := { name, type } :: context.locals }

def SymbolicBodyContext.bindMany
    (context : SymbolicBodyContext)
    (bindings : List SymbolicLocalBinding) : SymbolicBodyContext :=
  bindings.foldr (fun binding result => result.bind binding.name binding.type) context

theorem SymbolicBodyContext.bindMany_eq
    (context : SymbolicBodyContext)
    (bindings : List SymbolicLocalBinding) :
    context.bindMany bindings =
      { context with locals := bindings ++ context.locals } := by
  induction bindings generalizing context with
  | nil =>
      cases context
      rfl
  | cons head tail tailIH =>
      change (context.bindMany tail).bind head.name head.type = _
      rw [tailIH]
      cases context
      rfl

def SymbolicBodyContext.scopeContext
    (context : SymbolicBodyContext) : SourceWellFormed.Context := {
  globals := context.globals
  locals := context.locals.map (·.name)
}

inductive ResolvesSymbolicLocal :
    List SymbolicLocalBinding → Surface.Name → SymbolicLocalBinding → Prop where
  | head : ResolvesSymbolicLocal (binding :: outer) binding.name binding
  | tail
      (different : binding.name ≠ name)
      (resolved : ResolvesSymbolicLocal outer name selected) :
      ResolvesSymbolicLocal (binding :: outer) name selected

theorem ResolvesSymbolicLocal.member
    (resolved : ResolvesSymbolicLocal locals name binding) : binding ∈ locals := by
  induction resolved with
  | head => simp
  | tail different resolved induction => simp [induction]

theorem ResolvesSymbolicLocal.name
    {locals : List SymbolicLocalBinding} {requested : Surface.Name}
    {binding : SymbolicLocalBinding}
    (resolved : ResolvesSymbolicLocal locals requested binding) :
    binding.name = requested := by
  induction resolved with
  | head => rfl
  | tail different resolved induction => exact induction

/-- Symbolic lexical lookup has the same nearest-binding functionality as the
    concrete lookup it specializes. -/
theorem ResolvesSymbolicLocal.unique
    {locals : List SymbolicLocalBinding} {requested : Surface.Name}
    {leftBinding rightBinding : SymbolicLocalBinding}
    (left : ResolvesSymbolicLocal locals requested leftBinding)
    (right : ResolvesSymbolicLocal locals requested rightBinding) :
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

theorem ResolvesSymbolicLocal.scopeResolved
    (resolved : ResolvesSymbolicLocal locals requested binding) :
    SourceWellFormed.ResolvesLocal (locals.map (·.name)) requested := by
  induction resolved with
  | head => exact .head
  | tail different resolved induction => exact .tail different induction

theorem concreteLocalNameResolves
    (member : binding ∈ locals) :
    ∃ selected, SurfaceElaboration.ResolvesLocal locals binding.name selected := by
  induction locals with
  | nil => simp at member
  | cons head tail induction =>
      simp only [List.mem_cons] at member
      rcases member with equality | member
      · subst binding
        exact ⟨head, .head⟩
      · by_cases same : head.name = binding.name
        · exact ⟨head, same ▸ SurfaceElaboration.ResolvesLocal.head⟩
        · obtain ⟨selected, resolved⟩ := induction member
          exact ⟨selected, .tail same resolved⟩

/-- Concrete lexical bindings specialize symbolic bindings by name-resolution
    behavior, not by list position. Both directions are required: the forward
    direction preserves symbolic lookups, while the reverse direction rules
    out extra concrete bindings that would silently shadow a global name. -/
structure SymbolicLocalsSpecialize
    (substitution : Static.Substitution)
    (symbolic : List SymbolicLocalBinding)
    (concrete : List SurfaceElaboration.LocalBinding) : Prop where
  forward : ∀ name symbolicBinding,
    ResolvesSymbolicLocal symbolic name symbolicBinding →
    ∃ concreteBinding,
      SurfaceElaboration.ResolvesLocal concrete name concreteBinding ∧
      symbolicBinding.type.instantiate substitution = some concreteBinding.type
  reverse : ∀ name concreteBinding,
    SurfaceElaboration.ResolvesLocal concrete name concreteBinding →
    ∃ symbolicBinding,
      ResolvesSymbolicLocal symbolic name symbolicBinding ∧
      symbolicBinding.type.instantiate substitution = some concreteBinding.type

theorem SymbolicLocalsSpecialize.nil
    (substitution : Static.Substitution) :
    SymbolicLocalsSpecialize substitution [] [] := by
  constructor
  · intro name symbolicBinding resolved
    cases resolved
  · intro name concreteBinding resolved
    cases resolved

theorem SymbolicLocalsSpecialize.concrete_eq_nil
    (specialized : SymbolicLocalsSpecialize substitution [] concrete) :
    concrete = [] := by
  cases concreteFound : concrete with
  | nil => rfl
  | cons binding tail =>
      have bindingMember : binding ∈ concrete := by
        rw [concreteFound]
        simp
      obtain ⟨selected, resolved⟩ := concreteLocalNameResolves bindingMember
      obtain ⟨symbolicBinding, symbolicResolved, typeGrounds⟩ :=
        specialized.reverse binding.name selected resolved
      cases symbolicResolved

theorem SymbolicLocalsSpecialize.bind
    (name : Surface.Name) (id : VarId)
    (symbolicType : Static.Ty) (groundType : Static.GroundTy)
    (specialized : SymbolicLocalsSpecialize substitution symbolic concrete)
    (grounded : symbolicType.instantiate substitution = some groundType) :
    SymbolicLocalsSpecialize substitution
      ({ name, type := symbolicType } :: symbolic)
      ({ name, id, type := groundType } :: concrete) := by
  constructor
  · intro requested selected resolved
    cases resolved with
    | head => exact ⟨{ name, id, type := groundType }, .head, grounded⟩
    | tail different resolved =>
        obtain ⟨concreteBinding, concreteResolved, concreteType⟩ :=
          specialized.forward requested selected resolved
        exact ⟨concreteBinding, .tail different concreteResolved, concreteType⟩
  · intro requested selected resolved
    cases resolved with
    | head => exact ⟨{ name, type := symbolicType }, .head, grounded⟩
    | tail different resolved =>
        obtain ⟨symbolicBinding, symbolicResolved, concreteType⟩ :=
          specialized.reverse requested selected resolved
        exact ⟨symbolicBinding, .tail different symbolicResolved, concreteType⟩

theorem SymbolicLocalsSpecialize.noLocalNamed
    (specialized : SymbolicLocalsSpecialize substitution symbolic concrete)
    (absent : SourceWellFormed.NoLocalNamed (symbolic.map (·.name)) name) :
    SurfaceElaboration.NoLocalNamed concrete name := by
  intro binding member same
  obtain ⟨selected, resolved⟩ := concreteLocalNameResolves member
  have resolvedName : SurfaceElaboration.ResolvesLocal concrete name selected := by
    rw [← same]
    exact resolved
  obtain ⟨symbolicBinding, symbolicResolved, typeGrounds⟩ :=
    specialized.reverse name selected resolvedName
  exact absent symbolicBinding.name
    (List.mem_map.mpr ⟨symbolicBinding, symbolicResolved.member, rfl⟩)
    symbolicResolved.name

/-- A ground body context is the same declaration environment with one ground
    substitution and concrete lexical bindings whose lookup results specialize
    the symbolic bindings. -/
structure SymbolicBodyContext.Specializes
    (symbolic : SymbolicBodyContext)
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy)
    (concrete : SurfaceElaboration.Context) : Prop where
  globals : concrete = {
    symbolic.globals with
    substitution
    locals := concrete.locals
  }
  returnType : symbolic.returnType.instantiate substitution =
    some groundReturnType
  locals : SymbolicLocalsSpecialize substitution symbolic.locals concrete.locals

theorem SymbolicBodyContext.declarationSpecializes
    (base : SurfaceElaboration.Context)
    (assumptions : List Static.TraitPattern)
    (returnType : Static.Ty)
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy)
    (noLocals : base.locals = [])
    (returnGrounds : returnType.instantiate substitution =
      some groundReturnType) :
    ({
      globals := base
      assumptions
      returnType
      locals := []
    } : SymbolicBodyContext).Specializes substitution groundReturnType
      { base with substitution } := by
  refine ⟨?_, returnGrounds, ?_⟩
  · simp [noLocals]
  · simpa [noLocals] using SymbolicLocalsSpecialize.nil substitution

theorem SymbolicBodyContext.Specializes.bind
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (name : Surface.Name) (id : VarId)
    (symbolicType : Static.Ty) (groundType : Static.GroundTy)
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (grounded : symbolicType.instantiate substitution = some groundType) :
    (symbolic.bind name symbolicType).Specializes substitution groundReturnType
      (concrete.bindLocal name id groundType) := by
  refine ⟨?_, specialized.returnType,
    SymbolicLocalsSpecialize.bind name id symbolicType groundType
      specialized.locals grounded⟩
  exact congrArg
    (fun context => context.bindLocal name id groundType)
    specialized.globals

inductive SymbolicBindingsSpecialize
    (substitution : Static.Substitution) :
    List SymbolicLocalBinding → List SurfaceElaboration.LocalBinding → Prop where
  | nil : SymbolicBindingsSpecialize substitution [] []
  | cons
      (name : Surface.Name) (id : VarId)
      (typeGrounds : symbolicType.instantiate substitution = some groundType)
      (tail : SymbolicBindingsSpecialize substitution symbolicTail concreteTail) :
      SymbolicBindingsSpecialize substitution
        ({ name, type := symbolicType } :: symbolicTail)
        ({ name, id, type := groundType } :: concreteTail)

/-- Dense allocation for the lexical bindings introduced by one pattern.
    Unlike `SymbolicBindingsSpecialize`, this relation also records the local-ID
    supply consumed by the occurrence. Keeping allocation separate from pattern
    syntax lets nested variant patterns and statement lowering share one
    freshness argument. -/
inductive SymbolicBindingsAllocate
    (substitution : Static.Substitution) :
    VarId → List SymbolicLocalBinding →
      List SurfaceElaboration.LocalBinding → VarId → Prop where
  | nil (next : VarId) :
      SymbolicBindingsAllocate substitution next [] [] next
  | cons
      (typeGrounds : symbolicType.instantiate substitution = some groundType)
      (tail : SymbolicBindingsAllocate substitution (next + 1)
        symbolicTail concreteTail final) :
      SymbolicBindingsAllocate substitution next
        ({ name, type := symbolicType } :: symbolicTail)
        ({ name, id := next, type := groundType } :: concreteTail) final

theorem SymbolicBindingsAllocate.specializes
    (allocated : SymbolicBindingsAllocate substitution next symbolic concrete final) :
    SymbolicBindingsSpecialize substitution symbolic concrete := by
  induction allocated with
  | nil => exact .nil
  | cons typeGrounds tail tailIH => exact .cons _ _ typeGrounds tailIH

/-- Dense pattern allocation is a function of the symbolic bindings and the
    incoming local-ID supply. In particular, proof search cannot choose a
    different local ID or final supply for the same source bindings. -/
theorem SymbolicBindingsAllocate.unique
    (left : SymbolicBindingsAllocate substitution next symbolic
      concreteLeft finalLeft)
    (right : SymbolicBindingsAllocate substitution next symbolic
      concreteRight finalRight) :
    concreteLeft = concreteRight ∧ finalLeft = finalRight := by
  induction left generalizing concreteRight finalRight with
  | nil =>
      cases right
      exact ⟨rfl, rfl⟩
  | cons leftGrounds leftTail induction =>
      cases right with
      | cons rightGrounds rightTail =>
          have groundTypeEquality := Option.some.inj
            (leftGrounds.symm.trans rightGrounds)
          cases groundTypeEquality
          obtain ⟨concreteTailEquality, finalEquality⟩ := induction rightTail
          exact ⟨congrArg (fun tail => _ :: tail) concreteTailEquality,
            finalEquality⟩

theorem SymbolicBindingsAllocate.final_ge
    (allocated : SymbolicBindingsAllocate substitution next symbolic concrete final) :
    next ≤ final := by
  induction allocated with
  | nil => exact Nat.le_refl _
  | cons typeGrounds tail tailIH =>
      exact Nat.le_trans (Nat.le_succ _) tailIH

theorem SymbolicBindingsAllocate.ids_at_least
    (allocated : SymbolicBindingsAllocate substitution next symbolic concrete final) :
    ∀ binding, binding ∈ concrete → next ≤ binding.id := by
  induction allocated with
  | nil => simp
  | cons typeGrounds tail tailIH =>
      intro binding member
      simp only [List.mem_cons] at member
      rcases member with rfl | member
      · exact Nat.le_refl _
      · exact Nat.le_trans (Nat.le_succ _) (tailIH binding member)

theorem SymbolicBindingsAllocate.ids_below_final
    (allocated : SymbolicBindingsAllocate substitution next symbolic concrete final) :
    ∀ binding, binding ∈ concrete → binding.id < final := by
  induction allocated with
  | nil => simp
  | cons typeGrounds tail tailIH =>
      intro binding member
      simp only [List.mem_cons] at member
      rcases member with rfl | member
      · exact Nat.lt_of_lt_of_le (Nat.lt_succ_self _) tail.final_ge
      · exact tailIH binding member

theorem SymbolicBindingsAllocate.names
    (allocated : SymbolicBindingsAllocate substitution next symbolic concrete final) :
    concrete.map (·.name) = symbolic.map (·.name) := by
  induction allocated with
  | nil => rfl
  | cons typeGrounds tail tailIH => simp [tailIH]

theorem SymbolicBindingsAllocate.append
    (left : SymbolicBindingsAllocate substitution next
      symbolicLeft concreteLeft middle)
    (right : SymbolicBindingsAllocate substitution middle
      symbolicRight concreteRight final) :
    SymbolicBindingsAllocate substitution next
      (symbolicLeft ++ symbolicRight) (concreteLeft ++ concreteRight) final := by
  induction left with
  | nil => simpa using right
  | cons typeGrounds tail tailIH =>
      exact .cons typeGrounds (tailIH right)

theorem SymbolicBindingsAllocate.ids_pairwise
    (allocated : SymbolicBindingsAllocate substitution next symbolic concrete final) :
    concrete.Pairwise fun left right => left.id ≠ right.id := by
  induction allocated with
  | nil => exact .nil
  | cons typeGrounds tail tailIH =>
      apply List.Pairwise.cons
      · intro binding member same
        have later := tail.ids_at_least binding member
        exact Nat.ne_of_lt
          (Nat.lt_of_lt_of_le (Nat.lt_succ_self _) later) same
      · exact tailIH

theorem List.Pairwise.and
    {α : Type} {values : List α}
    {relationLeft relationRight : α → α → Prop}
    (left : values.Pairwise relationLeft)
    (right : values.Pairwise relationRight) :
    values.Pairwise fun first second =>
      relationLeft first second ∧ relationRight first second := by
  induction left with
  | nil => exact .nil
  | cons leftHead leftTail leftIH =>
      cases right with
      | cons rightHead rightTail =>
          exact .cons
            (fun value member => ⟨leftHead value member, rightHead value member⟩)
            (leftIH rightTail)

theorem SymbolicBindingsAllocate.patternBindingsFresh
    (allocated : SymbolicBindingsAllocate substitution next symbolic concrete final)
    (bounded : SurfaceElaboration.LocalIdsBelow context next)
    (namesDistinct : (symbolic.map (·.name)).Pairwise (· ≠ ·)) :
    SurfaceElaboration.PatternBindingsFresh context concrete := by
  constructor
  · intro binding member existing existingMember
    have existingBelow := bounded existing existingMember
    have allocatedAtLeast := allocated.ids_at_least binding member
    exact Nat.ne_of_lt (Nat.lt_of_lt_of_le existingBelow allocatedAtLeast)
  · have concreteNamesDistinct :
        (concrete.map (·.name)).Pairwise (· ≠ ·) := by
      rw [allocated.names]
      exact namesDistinct
    exact allocated.ids_pairwise.and
      (List.pairwise_map.mp concreteNamesDistinct)

theorem SurfaceElaboration.LocalIdsBelow.bindAllocated
    (bounded : SurfaceElaboration.LocalIdsBelow context next)
    (allocated : SymbolicBindingsAllocate substitution next symbolic concrete final) :
    SurfaceElaboration.LocalIdsBelow (context.bindLocals concrete) final := by
  intro binding member
  rw [SurfaceElaboration.Context.bindLocals_locals] at member
  rcases List.mem_append.mp member with introduced | existing
  · exact SymbolicBindingsAllocate.ids_below_final allocated binding introduced
  · exact Nat.lt_of_lt_of_le (bounded binding existing)
      (SymbolicBindingsAllocate.final_ge allocated)

theorem SymbolicBodyContext.Specializes.bindMany
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (bindings : SymbolicBindingsSpecialize substitution symbolicBindings
      concreteBindings) :
    (symbolic.bindMany symbolicBindings).Specializes substitution groundReturnType
      (concrete.bindLocals concreteBindings) := by
  induction bindings generalizing symbolic concrete with
  | nil => simpa [SymbolicBodyContext.bindMany,
      SurfaceElaboration.Context.bindLocals] using specialized
  | @cons groundType symbolicTail concreteTail symbolicType name id typeGrounds
      tail tailIH =>
      have specializedTail := tailIH specialized
      simpa [SymbolicBodyContext.bindMany,
        SurfaceElaboration.Context.bindLocals,
        SurfaceElaboration.Context.bindLocal] using
        specializedTail.bind name id symbolicType groundType typeGrounds

theorem SymbolicBodyContext.Specializes.globalPathNotShadowed
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (notShadowed : SourceWellFormed.GlobalPathNotShadowed
      symbolic.scopeContext path) :
    SurfaceElaboration.GlobalPathNotShadowed concrete path := by
  unfold SourceWellFormed.GlobalPathNotShadowed at notShadowed
  unfold SurfaceElaboration.GlobalPathNotShadowed
  cases found : SurfaceElaboration.unqualifiedPathName? path with
  | none => trivial
  | some name =>
      have symbolicAbsent : SourceWellFormed.NoLocalNamed
          (symbolic.locals.map (·.name)) name := by
        simpa [found, SymbolicBodyContext.scopeContext] using notShadowed
      exact specialized.locals.noLocalNamed symbolicAbsent

theorem SymbolicBodyContext.Specializes.substitution
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete) :
    concrete.substitution = substitution := by
  rw [specialized.globals]

theorem SymbolicBodyContext.Specializes.resolvesTypeParameter
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (resolved : SurfaceElaboration.ResolvesTypeParameter
      symbolic.globals.typeParameters name binding) :
    SurfaceElaboration.ResolvesTypeParameter concrete.typeParameters name binding := by
  rw [specialized.globals]
  exact resolved

theorem SymbolicBodyContext.Specializes.globalTypePathNotShadowed
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (notShadowed : SurfaceElaboration.GlobalTypePathNotShadowed
      symbolic.globals path) :
    SurfaceElaboration.GlobalTypePathNotShadowed concrete path := by
  unfold SurfaceElaboration.GlobalTypePathNotShadowed at notShadowed ⊢
  rw [specialized.globals]
  exact notShadowed

theorem SymbolicBodyContext.Specializes.resolvesConstParameter
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (resolved : SurfaceElaboration.ResolvesConstParameter
      symbolic.globals.constParameters name binding) :
    SurfaceElaboration.ResolvesConstParameter concrete.constParameters name binding := by
  rw [specialized.globals]
  exact resolved

theorem SymbolicBodyContext.Specializes.resolvesGlobal
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (resolved : SurfaceElaboration.ResolvesGlobal
      symbolic.globals lookupNamespace path symbol) :
    SurfaceElaboration.ResolvesGlobal concrete lookupNamespace path symbol := by
  cases resolved with
  | intro reference formed namesResolved =>
      apply SurfaceElaboration.ResolvesGlobal.intro reference formed
      rw [specialized.globals]
      exact namesResolved

theorem SymbolicBodyContext.Specializes.reflectsGlobal
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (resolved : SurfaceElaboration.ResolvesGlobal
      concrete lookupNamespace path symbol) :
    SurfaceElaboration.ResolvesGlobal symbolic.globals lookupNamespace path symbol := by
  cases resolved with
  | intro reference formed namesResolved =>
      apply SurfaceElaboration.ResolvesGlobal.intro reference formed
      rw [specialized.globals] at namesResolved
      exact namesResolved

theorem SymbolicBodyContext.Specializes.noGlobalValueResolution
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (absent : SurfaceElaboration.NoGlobalValueResolution symbolic.globals path) :
    SurfaceElaboration.NoGlobalValueResolution concrete path := by
  intro symbol resolved
  exact absent symbol (specialized.reflectsGlobal resolved)

theorem SymbolicBodyContext.Specializes.nominalSchemeMember
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (member : scheme ∈ symbolic.globals.nominalSchemes) :
    scheme ∈ concrete.nominalSchemes := by
  rw [specialized.globals]
  exact member

/-- Close one finite nominal-artifact demand. All generic and trait evidence is
    derived by composing the constructor's symbolic substitution with the
    enclosing ground substitution; only membership and identity of the emitted
    artifact row remain occurrence-specific inputs. -/
theorem SymbolicBodyContext.Specializes.nominalConstructorInstantiates
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (arguments : Static.SymbolicArgumentsBound symbolicSubstitution parameters
      symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution requirementPatterns)
    (member : resolved ∈ concrete.nominalInstances)
    (resolvedDeclaration : resolved.declaration = declaration)
    (resolvedSourceType : resolved.sourceType = sourceType)
    (resolvedKind : resolved.kind = kind)
    (resolvedTypeArguments : resolved.typeArguments = groundTypeArguments)
    (resolvedConstArguments : resolved.constArguments = groundConstArguments)
    (unique : ∀ candidate,
      candidate ∈ concrete.nominalInstances →
      candidate.sourceType = sourceType →
      candidate.typeArguments = resolved.typeArguments →
      candidate.constArguments = resolved.constArguments →
      candidate.coreType = resolved.coreType) :
    SurfaceElaboration.NominalConstructorInstantiates concrete declaration
      sourceType kind parameters requirementPatterns
      (symbolicSubstitution.composeGround outer) resolved := by
  refine ⟨member, resolvedDeclaration, resolvedSourceType, resolvedKind, ?_, ?_, unique⟩
  · rw [resolvedTypeArguments, resolvedConstArguments]
    exact arguments.composeGround typeArgumentsGround constArgumentsGround
  · have grounded := requirements.ground
    have implementations :
        concrete.implementations = symbolic.globals.implementations := by
      rw [contexts.globals]
    rw [implementations]
    exact grounded

/-- The finite artifact-table portion of a nominal constructor demand. Generic
    argument binding and trait satisfaction are deliberately absent: they are
    derived from the symbolic occurrence by the specialization theorem. -/
inductive NominalArtifactDemand
    (concrete : SurfaceElaboration.Context)
    (declaration : Nat) (sourceType : TypeId) (kind : Static.NominalKind)
    (groundTypeArguments : List Static.GroundTy)
    (groundConstArguments : List Nat)
    (resolved : Static.NominalInstance) : Prop where
  | intro
      (member : resolved ∈ concrete.nominalInstances)
      (resolvedDeclaration : resolved.declaration = declaration)
      (resolvedSourceType : resolved.sourceType = sourceType)
      (resolvedKind : resolved.kind = kind)
      (resolvedTypeArguments : resolved.typeArguments = groundTypeArguments)
      (resolvedConstArguments : resolved.constArguments = groundConstArguments)
      (unique : ∀ candidate,
        candidate ∈ concrete.nominalInstances →
        candidate.sourceType = sourceType →
        candidate.typeArguments = resolved.typeArguments →
        candidate.constArguments = resolved.constArguments →
        candidate.coreType = resolved.coreType) :
      NominalArtifactDemand concrete declaration sourceType kind
        groundTypeArguments groundConstArguments resolved

theorem NominalArtifactDemand.typeArguments
    (demand : NominalArtifactDemand concrete declaration sourceType kind
      groundTypeArguments groundConstArguments resolved) :
    resolved.typeArguments = groundTypeArguments := by
  cases demand
  assumption

theorem NominalArtifactDemand.constArguments
    (demand : NominalArtifactDemand concrete declaration sourceType kind
      groundTypeArguments groundConstArguments resolved) :
    resolved.constArguments = groundConstArguments := by
  cases demand
  assumption

theorem NominalArtifactDemand.instantiates
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (demand : NominalArtifactDemand concrete declaration sourceType kind
      groundTypeArguments groundConstArguments resolved)
    (arguments : Static.SymbolicArgumentsBound symbolicSubstitution parameters
      symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution requirementPatterns) :
    SurfaceElaboration.NominalConstructorInstantiates concrete declaration
      sourceType kind parameters requirementPatterns
      (symbolicSubstitution.composeGround outer) resolved := by
  cases demand with
  | intro member resolvedDeclaration resolvedSourceType resolvedKind
      resolvedTypeArguments resolvedConstArguments unique =>
      exact contexts.nominalConstructorInstantiates arguments typeArgumentsGround
        constArgumentsGround requirements member resolvedDeclaration
        resolvedSourceType resolvedKind resolvedTypeArguments
        resolvedConstArguments unique

/-- The finite emitted-row portion of one direct-call specialization. The
    source declaration, generic binding, instantiated signature, and trait
    obligations are intentionally not repeated here: those are consequences
    of the symbolic call occurrence. The final field states only the artifact
    table's uniqueness policy for rows of that already-selected declaration. -/
inductive FunctionArtifactDemand
    (concrete : SurfaceElaboration.Context) (path : Surface.Path)
    (scheme : Static.FunctionScheme)
    (groundTypeArguments : List Static.GroundTy)
    (groundConstArguments : List Nat)
    (resolved : Static.FunctionInstance) : Prop where
  | intro
      (member : resolved ∈ concrete.functionInstances)
      (resolvedDeclaration : resolved.declaration = scheme.declaration)
      (resolvedTypeArguments : resolved.typeArguments = groundTypeArguments)
      (resolvedConstArguments : resolved.constArguments = groundConstArguments)
      (unique : ∀ candidateSubstitution candidate,
        candidate ∈ concrete.functionInstances →
        Static.FunctionInstantiates concrete.implementations scheme
          candidateSubstitution candidate →
        candidate.parameterTypes = resolved.parameterTypes →
        SurfaceElaboration.ExplicitCallArgumentsGround concrete path
          scheme.genericParameters candidateSubstitution →
        candidate.function = resolved.function) :
      FunctionArtifactDemand concrete path scheme groundTypeArguments
        groundConstArguments resolved

/-- Symbolic generic binding followed by an enclosing ground substitution
    constructs the complete static instantiation certificate for the demanded
    function row. Nothing about the row's parameter or return types is assumed:
    both are derived by substitution composition. -/
theorem FunctionArtifactDemand.instantiates
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (demand : FunctionArtifactDemand concrete path scheme groundTypeArguments
      groundConstArguments resolved)
    (arguments : Static.SymbolicArgumentsBound inner scheme.genericParameters
      symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer inner
      scheme.requirements)
    (parametersSubstitute : Static.substituteTypes inner scheme.parameterTypes =
      some symbolicParameterTypes)
    (parametersGround : Static.instantiateTypes outer symbolicParameterTypes =
      some resolved.parameterTypes)
    (returnSubstitute : scheme.returnType.substitute inner =
      some symbolicReturnType)
    (returnGround : symbolicReturnType.instantiate outer =
      some resolved.returnType) :
    Static.FunctionInstantiates concrete.implementations scheme
      (inner.composeGround outer) resolved := by
  cases demand with
  | intro member resolvedDeclaration resolvedTypeArguments
      resolvedConstArguments unique =>
      have implementations : concrete.implementations =
          symbolic.globals.implementations := by
        rw [contexts.globals]
      apply Static.FunctionInstantiates.intro
      · exact (arguments.parametersGround typeArgumentsGround
          constArgumentsGround).parametersBound
      · rw [resolvedTypeArguments, resolvedConstArguments]
        exact arguments.composeGround typeArgumentsGround constArgumentsGround
      · rw [implementations]
        exact requirements.ground
      · have parameterTypes := Static.substituteTypes_then_instantiate
          parametersSubstitute parametersGround
        have returnType := Static.Ty.substitute_then_instantiate
          returnSubstitute returnGround
        unfold Static.FunctionScheme.instantiateTypes
        simp [parameterTypes, returnType]
        cases resolved
        simp_all

/-- Close one source-selected direct call against one finite emitted function
    row. Source lookup supplies the declaration identity; substitution supplies
    its signature and obligations; the demand supplies only row membership and
    uniqueness. -/
theorem FunctionArtifactDemand.resolvesDirectCall
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (selected : SourceWellFormed.SelectsFunction
      symbolic.scopeContext path scheme)
    (demand : FunctionArtifactDemand concrete path scheme groundTypeArguments
      groundConstArguments resolved)
    (arguments : Static.SymbolicArgumentsBound inner scheme.genericParameters
      symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer inner
      scheme.requirements)
    (parametersSubstitute : Static.substituteTypes inner scheme.parameterTypes =
      some symbolicParameterTypes)
    (parametersGround : Static.instantiateTypes outer symbolicParameterTypes =
      some resolved.parameterTypes)
    (returnSubstitute : scheme.returnType.substitute inner =
      some symbolicReturnType)
    (returnGround : symbolicReturnType.instantiate outer =
      some resolved.returnType)
    (explicitArguments : SurfaceElaboration.ExplicitCallArgumentsGround concrete
      path scheme.genericParameters (inner.composeGround outer)) :
    SurfaceElaboration.ResolvesDirectCall concrete path resolved.parameterTypes
      scheme resolved := by
  rcases selected with
    ⟨notShadowed, symbol, sourceResolved, schemeMember, declaration,
      schemeUnique⟩
  cases demand with
  | intro instanceMember resolvedDeclaration resolvedTypeArguments
      resolvedConstArguments instanceUnique =>
      have concreteSchemeMember : scheme ∈ concrete.functions := by
        rw [contexts.globals]
        exact schemeMember
      have instantiated : Static.FunctionInstantiates concrete.implementations
          scheme (inner.composeGround outer) resolved := by
        exact FunctionArtifactDemand.instantiates contexts
          (.intro instanceMember resolvedDeclaration resolvedTypeArguments
            resolvedConstArguments instanceUnique)
          arguments typeArgumentsGround constArgumentsGround requirements
          parametersSubstitute parametersGround returnSubstitute returnGround
      refine ⟨contexts.globalPathNotShadowed notShadowed, symbol,
        contexts.resolvesGlobal sourceResolved, concreteSchemeMember, declaration,
        ⟨instanceMember, inner.composeGround outer, instantiated, rfl,
          explicitArguments⟩, ?_⟩
      intro candidate candidateInstance candidateMember candidateDeclaration
        candidateApplies
      have sourceCandidateMember : candidate ∈ symbolic.globals.functions := by
        rw [contexts.globals] at candidateMember
        exact candidateMember
      have candidateEquality : candidate = scheme :=
        schemeUnique candidate sourceCandidateMember candidateDeclaration
      subst candidate
      rcases candidateApplies with
        ⟨candidateInstanceMember, candidateSubstitution,
          candidateInstantiated, candidateParameters, candidateExplicit⟩
      exact instanceUnique candidateSubstitution candidateInstance
        candidateInstanceMember candidateInstantiated candidateParameters
        candidateExplicit

/-- The finite emitted-row portion of one method specialization. Generic
    binding, signature grounding, trait discharge, and lookup stability live
    outside this record because they are properties of the typed occurrence,
    not facts that should be duplicated in an artifact catalog. -/
inductive MethodArtifactDemand
    (concrete : SurfaceElaboration.Context)
    (scheme : Static.MethodScheme)
    (groundTypeArguments : List Static.GroundTy)
    (groundConstArguments : List Nat)
    (resolved : Static.MethodInstance) : Prop where
  | intro
      (member : resolved ∈ concrete.methodInstances)
      (declaration : resolved.declaration = scheme.declaration)
      (name : resolved.name = scheme.name)
      (receiverMode : resolved.receiverMode = scheme.receiverMode)
      (typeArguments : resolved.typeArguments = groundTypeArguments)
      (constArguments : resolved.constArguments = groundConstArguments)
      (unique : ∀ candidateSubstitution candidate,
        candidate ∈ concrete.methodInstances →
        Static.MethodInstantiates concrete.implementations scheme
          candidateSubstitution candidate →
        candidate.receiverType = resolved.receiverType →
        candidate.name = resolved.name →
        candidate.argumentTypes = resolved.argumentTypes →
        candidate.function = resolved.function) :
      MethodArtifactDemand concrete scheme groundTypeArguments
        groundConstArguments resolved

theorem MethodArtifactDemand.instantiates
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (demand : MethodArtifactDemand concrete scheme groundTypeArguments
      groundConstArguments resolved)
    (arguments : Static.SymbolicArgumentsBound inner scheme.genericParameters
      symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer inner
      scheme.requirements)
    (receiverSubstitute : scheme.receiverType.substitute inner =
      some symbolicReceiver)
    (receiverGround : symbolicReceiver.instantiate outer =
      some resolved.receiverType)
    (argumentsSubstitute : Static.substituteTypes inner scheme.argumentTypes =
      some symbolicArguments)
    (argumentsGround : Static.instantiateTypes outer symbolicArguments =
      some resolved.argumentTypes)
    (returnSubstitute : scheme.returnType.substitute inner =
      some symbolicResult)
    (returnGround : symbolicResult.instantiate outer =
      some resolved.returnType) :
    Static.MethodInstantiates concrete.implementations scheme
      (inner.composeGround outer) resolved := by
  cases demand with
  | intro member declaration name receiverMode typeArguments constArguments
      unique =>
      have implementations : concrete.implementations =
          symbolic.globals.implementations := by
        rw [contexts.globals]
      apply Static.MethodInstantiates.inherent
      · exact (arguments.parametersGround typeArgumentsGround
          constArgumentsGround).parametersBound
      · rw [typeArguments, constArguments]
        exact arguments.composeGround typeArgumentsGround constArgumentsGround
      · rw [implementations]
        exact requirements.ground
      · have receiverType := Static.Ty.substitute_then_instantiate
          receiverSubstitute receiverGround
        have argumentTypes := Static.substituteTypes_then_instantiate
          argumentsSubstitute argumentsGround
        have returnType := Static.Ty.substitute_then_instantiate
          returnSubstitute returnGround
        unfold Static.MethodScheme.instantiateTypes
        simp [receiverType, argumentTypes, returnType]
        cases resolved
        simp_all

/-- Close one method call from a coherent finite method table. Unlike a raw
    lowering premise, program-wide receiver/name lookup coherence proves the
    symbolic declaration remains selected after grounding, while the
    occurrence's artifact demand fixes the exact emitted specialization row. -/
theorem MethodArtifactDemand.resolvesMethod
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (schemeMember : scheme ∈ symbolic.globals.methods)
    (schemeName : scheme.name = name)
    (memberMode : scheme.receiverMode ≠ .none)
    (demand : MethodArtifactDemand concrete scheme groundTypeArguments
      groundConstArguments resolved)
    (arguments : Static.SymbolicArgumentsBound inner scheme.genericParameters
      symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer inner
      scheme.requirements)
    (receiverSubstitute : scheme.receiverType.substitute inner =
      some symbolicReceiver)
    (receiverGround : symbolicReceiver.instantiate outer =
      some groundReceiver)
    (argumentsSubstitute : Static.substituteTypes inner scheme.argumentTypes =
      some symbolicArguments)
    (argumentsGround : Static.instantiateTypes outer symbolicArguments =
      some groundArguments)
    (returnSubstitute : scheme.returnType.substitute inner =
      some symbolicResult)
    (returnGround : symbolicResult.instantiate outer = some groundResult)
    (resolvedReceiver : resolved.receiverType = groundReceiver)
    (resolvedArguments : resolved.argumentTypes = groundArguments)
    (resolvedResult : resolved.returnType = groundResult)
    (selectedPreferred : scheme.preferredAt concrete.methods
      concrete.currentModule
      (Static.GroundMethodLookupApplicable concrete.implementations
        concrete.methodInstances groundReceiver name))
    (coherent : Static.MethodLookupCoherent concrete.implementations
      concrete.methods concrete.methodInstances) :
    Static.ResolvesMethod concrete.implementations concrete.methods
      concrete.methodInstances concrete.currentModule groundReceiver name
      groundArguments scheme resolved := by
  cases demand with
  | intro instanceMember declaration instanceName instanceReceiverMode
      typeArguments constArguments instanceUnique =>
      have concreteSchemeMember : scheme ∈ concrete.methods := by
        rw [contexts.globals]
        exact schemeMember
      have instantiated : Static.MethodInstantiates concrete.implementations
          scheme (inner.composeGround outer) resolved := by
        have receiverGroundResolved : symbolicReceiver.instantiate outer =
            some resolved.receiverType :=
          receiverGround.trans (congrArg some resolvedReceiver.symm)
        have argumentsGroundResolved : Static.instantiateTypes outer
            symbolicArguments = some resolved.argumentTypes :=
          argumentsGround.trans (congrArg some resolvedArguments.symm)
        have returnGroundResolved : symbolicResult.instantiate outer =
            some resolved.returnType :=
          returnGround.trans (congrArg some resolvedResult.symm)
        exact MethodArtifactDemand.instantiates contexts
          (.intro instanceMember declaration instanceName instanceReceiverMode
            typeArguments constArguments instanceUnique)
          arguments typeArgumentsGround constArgumentsGround requirements
          receiverSubstitute receiverGroundResolved argumentsSubstitute
          argumentsGroundResolved returnSubstitute returnGroundResolved
      have signature := instantiated.signature
      have resolvedName : resolved.name = name := signature.2.2.2.2.1.trans schemeName
      have selectedApplies : scheme.applies concrete.implementations
          concrete.methodInstances groundReceiver name groundArguments resolved :=
        ⟨instanceMember, inner.composeGround outer, instantiated,
          resolvedReceiver, resolvedName, resolvedArguments⟩
      have resolvedMemberMode : resolved.receiverMode ≠ .none := by
        intro resolvedNone
        exact memberMode (signature.2.2.2.2.2.symm.trans resolvedNone)
      have stable := coherent concrete.currentModule groundReceiver name
        scheme concreteSchemeMember
        ⟨groundArguments, resolved, selectedApplies⟩ selectedPreferred
      refine ⟨concreteSchemeMember, ⟨selectedApplies, resolvedMemberMode⟩,
        selectedPreferred, ?_⟩
      intro candidate candidateInstance candidateMember candidateApplies
        candidatePreferred
      have candidateEquality := stable candidate candidateMember
        ⟨groundArguments, candidateInstance, candidateApplies.1⟩ candidatePreferred
      subst candidate
      rcases candidateApplies.1 with
        ⟨candidateInstanceMember, candidateSubstitution,
          candidateInstantiated, candidateReceiver, candidateName,
          candidateArguments⟩
      exact instanceUnique candidateSubstitution candidateInstance
        candidateInstanceMember candidateInstantiated
        (candidateReceiver.trans resolvedReceiver.symm)
        (candidateName.trans resolvedName.symm)
        (candidateArguments.trans resolvedArguments.symm)

/-- Close a type-qualified inherent-function call against the same coherent
    receiver/name table used by member lookup. The associated argument view is
    projected from each emitted instance; equality of that view recovers the
    stored argument-vector equality required by artifact identity. -/
theorem MethodArtifactDemand.resolvesAssociatedMethod
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (schemeMember : scheme ∈ symbolic.globals.methods)
    (schemeName : scheme.name = name)
    (demand : MethodArtifactDemand concrete scheme groundTypeArguments
      groundConstArguments resolved)
    (arguments : Static.SymbolicArgumentsBound inner scheme.genericParameters
      symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer inner
      scheme.requirements)
    (receiverSubstitute : scheme.receiverType.substitute inner =
      some symbolicReceiver)
    (receiverGround : symbolicReceiver.instantiate outer = some groundReceiver)
    (storedArgumentsSubstitute : Static.substituteTypes inner scheme.argumentTypes =
      some symbolicStoredArguments)
    (storedArgumentsGround : Static.instantiateTypes outer symbolicStoredArguments =
      some resolved.argumentTypes)
    (returnSubstitute : scheme.returnType.substitute inner = some symbolicResult)
    (returnGround : symbolicResult.instantiate outer = some resolved.returnType)
    (resolvedReceiver : resolved.receiverType = groundReceiver)
    (resolvedAssociatedArguments : resolved.associatedArgumentTypes? =
      some groundArguments)
    (selectedPreferred : scheme.preferredAt concrete.methods
      concrete.currentModule
      (Static.GroundMethodLookupApplicable concrete.implementations
        concrete.methodInstances groundReceiver name))
    (coherent : Static.MethodLookupCoherent concrete.implementations
      concrete.methods concrete.methodInstances) :
    Static.ResolvesAssociatedMethod concrete.implementations concrete.methods
      concrete.methodInstances concrete.currentModule groundReceiver name
      groundArguments scheme resolved := by
  cases demand with
  | intro instanceMember declaration instanceName instanceReceiverMode
      typeArguments constArguments instanceUnique =>
      have concreteSchemeMember : scheme ∈ concrete.methods := by
        rw [contexts.globals]
        exact schemeMember
      have instantiated : Static.MethodInstantiates concrete.implementations
          scheme (inner.composeGround outer) resolved := by
        exact MethodArtifactDemand.instantiates contexts
          (.intro instanceMember declaration instanceName instanceReceiverMode
            typeArguments constArguments instanceUnique)
          arguments typeArgumentsGround constArgumentsGround requirements
          receiverSubstitute
          (receiverGround.trans (congrArg some resolvedReceiver.symm))
          storedArgumentsSubstitute storedArgumentsGround returnSubstitute
          returnGround
      have signature := instantiated.signature
      have resolvedName : resolved.name = name :=
        signature.2.2.2.2.1.trans schemeName
      have selectedApplies : scheme.appliesAssociated concrete.implementations
          concrete.methodInstances groundReceiver name groundArguments resolved :=
        ⟨instanceMember, inner.composeGround outer, instantiated,
          resolvedReceiver, resolvedName, resolvedAssociatedArguments⟩
      have selectedOrdinary : scheme.applies concrete.implementations
          concrete.methodInstances groundReceiver name resolved.argumentTypes
          resolved :=
        ⟨instanceMember, inner.composeGround outer, instantiated,
          resolvedReceiver, resolvedName, rfl⟩
      have stable := coherent concrete.currentModule groundReceiver name scheme
        concreteSchemeMember
        ⟨resolved.argumentTypes, resolved, selectedOrdinary⟩ selectedPreferred
      refine ⟨concreteSchemeMember, selectedApplies, selectedPreferred, ?_⟩
      intro candidate candidateInstance candidateMember candidateApplies
        candidatePreferred
      rcases candidateApplies with
        ⟨candidateInstanceMember, candidateSubstitution,
          candidateInstantiated, candidateReceiver, candidateName,
          candidateAssociatedArguments⟩
      have candidateSignature := candidateInstantiated.signature
      have candidateOrdinary : candidate.applies concrete.implementations
          concrete.methodInstances groundReceiver name candidateInstance.argumentTypes
          candidateInstance :=
        ⟨candidateInstanceMember, candidateSubstitution, candidateInstantiated,
          candidateReceiver, candidateName, rfl⟩
      have candidateEquality := stable candidate candidateMember
        ⟨candidateInstance.argumentTypes, candidateInstance, candidateOrdinary⟩
        candidatePreferred
      subst candidate
      have modesEqual : candidateInstance.receiverMode = resolved.receiverMode :=
        candidateSignature.2.2.2.2.2.trans signature.2.2.2.2.2.symm
      unfold Static.MethodInstance.associatedArgumentTypes? at candidateAssociatedArguments resolvedAssociatedArguments
      rw [modesEqual] at candidateAssociatedArguments
      have storedArgumentsEqual :
          candidateInstance.argumentTypes = resolved.argumentTypes := by
        cases mode : resolved.receiverMode with
        | none =>
            simp [mode]
              at candidateAssociatedArguments resolvedAssociatedArguments
            exact candidateAssociatedArguments.trans
              resolvedAssociatedArguments.symm
        | explicit =>
            simp [mode]
              at candidateAssociatedArguments resolvedAssociatedArguments
            exact (List.cons.inj
              (candidateAssociatedArguments.trans
                resolvedAssociatedArguments.symm)).2
        | value =>
            simp [mode]
              at resolvedAssociatedArguments
        | reference =>
            simp [mode]
              at resolvedAssociatedArguments
      exact instanceUnique candidateSubstitution candidateInstance
        candidateInstanceMember candidateInstantiated
        (candidateReceiver.trans resolvedReceiver.symm)
        (candidateName.trans resolvedName.symm) storedArgumentsEqual

/-- The concrete enum-layout row demanded by one source variant occurrence.
    Its receiver and payload are the grounding of the symbolic enum scheme;
    row identity and duplicate agreement are the only catalog facts retained. -/
inductive VariantArtifactDemand
    (concrete : SurfaceElaboration.Context)
    (constructor : SurfaceElaboration.VariantConstructorScheme)
    (groundReceiver : Static.GroundTy)
    (groundPayload : List Static.GroundTy)
    (entry : SurfaceElaboration.VariantEntry) : Prop where
  | intro
      (member : entry ∈ concrete.variants)
      (declaration : entry.declaration = constructor.declaration)
      (receiver : entry.receiver = groundReceiver)
      (variant : entry.variant = constructor.variant)
      (payload : entry.payload = groundPayload)
      (unique : ∀ candidate,
        candidate ∈ concrete.variants →
        candidate.declaration = constructor.declaration →
        candidate.receiver = groundReceiver →
        candidate.coreType = entry.coreType ∧
          candidate.variant = entry.variant ∧
          candidate.payload = entry.payload) :
      VariantArtifactDemand concrete constructor groundReceiver groundPayload entry

theorem VariantArtifactDemand.receiver
    (demand : VariantArtifactDemand concrete constructor groundReceiver
      groundPayload entry) :
    entry.receiver = groundReceiver := by
  cases demand
  assumption

theorem VariantArtifactDemand.payload
    (demand : VariantArtifactDemand concrete constructor groundReceiver
      groundPayload entry) :
    entry.payload = groundPayload := by
  cases demand
  assumption

/-- Two demanded rows for the same grounded source variant agree on every
    core-pattern field. This is the artifact-level functional dependency used
    by exact pattern specialization. -/
theorem VariantArtifactDemand.agrees
    (left : VariantArtifactDemand concrete constructor groundReceiver
      groundPayload leftEntry)
    (right : VariantArtifactDemand concrete constructor groundReceiver
      groundPayload rightEntry) :
    rightEntry.coreType = leftEntry.coreType ∧
      rightEntry.variant = leftEntry.variant ∧
      rightEntry.payload = leftEntry.payload := by
  cases left with
  | intro leftMember leftDeclaration leftReceiver leftVariant leftPayload
      leftUnique =>
      cases right with
      | intro rightMember rightDeclaration rightReceiver rightVariant
          rightPayload rightUnique =>
          exact leftUnique rightEntry rightMember rightDeclaration rightReceiver

/-- Retaining a source annotation and then grounding its symbolic type is the
    same operation as resolving that annotation directly in the monomorphic
    context. This includes nested nominal arguments and const-generic array
    lengths; it is the annotation boundary used by specialized statements and
    patterns. -/
theorem TypeRetains.specializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType groundType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (retained : TypeRetains symbolic.globals surfaceType symbolicType)
    (grounded : symbolicType.instantiate substitution = some groundType) :
    SurfaceElaboration.TypeGrounds concrete surfaceType groundType := by
  refine TypeRetains.rec
    (motive_1 := fun surface retained _ => ∀ ground,
      retained.instantiate substitution = some ground →
        SurfaceElaboration.TypeGrounds concrete surface ground)
    (motive_2 := fun surfaces retained _ => ∀ grounds,
      Static.instantiateTypes substitution retained = some grounds →
        SurfaceElaboration.TypesGround concrete surfaces grounds)
    (motive_3 := fun surface retained _ => ∀ ground,
      retained.instantiate substitution = some ground →
        SurfaceElaboration.ArrayLengthGrounds concrete surface ground)
    (motive_4 := fun surface retained _ => ∀ ground,
      retained.instantiate substitution = some ground →
        SurfaceElaboration.ConstTypeArgumentGrounds concrete surface ground)
    (motive_5 := fun parameters surfaces retainedTypes retainedConstants _ =>
      ∀ groundTypes groundConstants,
        Static.instantiateTypes substitution retainedTypes = some groundTypes →
        Static.instantiateConstants substitution retainedConstants =
          some groundConstants →
        SurfaceElaboration.NominalArgumentsGround concrete parameters surfaces
          groundTypes groundConstants)
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_
    retained groundType grounded
  · intro segments name scalar single found ground typeGrounds
    simp [Static.Ty.instantiate] at typeGrounds
    subst ground
    exact .builtin single found
  · intro segments name binding single notBuiltin resolved ground typeGrounds
    exact .parameter single notBuiltin (contexts.resolvesTypeParameter resolved)
      (by simpa [Static.Ty.instantiate, contexts.substitution] using typeGrounds)
  · intro segments scheme surfaceArguments retainedTypes retainedConstants symbol
      notBuiltin notShadowed resolved member declaration argumentsFound arguments
      argumentsIH ground typeGrounds
    cases typesGrounded : Static.instantiateTypes substitution retainedTypes with
    | none =>
        simp [Static.Ty.instantiate, typesGrounded] at typeGrounds
    | some groundTypes =>
        cases constantsGrounded : Static.instantiateConstants substitution
          retainedConstants with
        | none =>
            simp [Static.Ty.instantiate, typesGrounded, constantsGrounded]
              at typeGrounds
        | some groundConstants =>
            simp [Static.Ty.instantiate, typesGrounded, constantsGrounded]
              at typeGrounds
            subst ground
            exact .nominal symbol notBuiltin
              (contexts.globalTypePathNotShadowed notShadowed)
              (contexts.resolvesGlobal resolved)
              (contexts.nominalSchemeMember member)
              declaration argumentsFound
              (argumentsIH groundTypes groundConstants typesGrounded
                constantsGrounded)
  · intro surfaceElement retainedElement surfaceLength retainedLength element
      length elementIH lengthIH ground typeGrounds
    cases elementGrounded : retainedElement.instantiate substitution with
    | none =>
        simp [Static.Ty.instantiate, elementGrounded] at typeGrounds
    | some groundElement =>
        cases lengthGrounded : retainedLength.instantiate substitution with
        | none =>
            simp [Static.Ty.instantiate, elementGrounded, lengthGrounded]
              at typeGrounds
        | some groundLength =>
            simp [Static.Ty.instantiate, elementGrounded, lengthGrounded]
              at typeGrounds
            subst ground
            exact .array (elementIH groundElement elementGrounded)
              (lengthIH groundLength lengthGrounded)
  · intro surfaceElement retainedElement element elementIH ground typeGrounds
    cases elementGrounded : retainedElement.instantiate substitution with
    | none => simp [Static.Ty.instantiate, elementGrounded] at typeGrounds
    | some groundElement =>
        simp [Static.Ty.instantiate, elementGrounded] at typeGrounds
        subst ground
        exact .slice (elementIH groundElement elementGrounded)
  · intro surfaceReferent retainedReferent referent referentIH ground typeGrounds
    cases referentGrounded : retainedReferent.instantiate substitution with
    | none => simp [Static.Ty.instantiate, referentGrounded] at typeGrounds
    | some groundReferent =>
        simp [Static.Ty.instantiate, referentGrounded] at typeGrounds
        subst ground
        exact .reference (referentIH groundReferent referentGrounded)
  · intro grounds typesGrounds
    simp [Static.instantiateTypes] at typesGrounds
    subst grounds
    exact .nil
  · intro surfaceHead retainedHead surfaceTail retainedTail head tail headIH
      tailIH grounds typesGrounds
    cases headGrounded : retainedHead.instantiate substitution with
    | none => simp [Static.instantiateTypes, headGrounded] at typesGrounds
    | some groundHead =>
        cases tailGrounded : Static.instantiateTypes substitution retainedTail with
        | none =>
            simp [Static.instantiateTypes, headGrounded, tailGrounded]
              at typesGrounds
        | some groundTail =>
            simp [Static.instantiateTypes, headGrounded, tailGrounded]
              at typesGrounds
            subst grounds
            exact .cons (headIH groundHead headGrounded)
              (tailIH groundTail tailGrounded)
  · intro value ground constGrounds
    simp [Static.Const.instantiate] at constGrounds
    subst ground
    exact .literal
  · intro name binding resolved ground constGrounds
    exact .parameter (contexts.resolvesConstParameter resolved)
      (by simpa [Static.Const.instantiate, contexts.substitution] using constGrounds)
  · intro segments name binding single resolved ground constGrounds
    exact .parameter single (contexts.resolvesConstParameter resolved)
      (by simpa [Static.Const.instantiate, contexts.substitution] using constGrounds)
  · intro groundTypes groundConstants typesGrounded constantsGrounded
    simp [Static.instantiateTypes] at typesGrounded
    simp [Static.instantiateConstants] at constantsGrounded
    subst groundTypes
    subst groundConstants
    exact .nil
  · intro surfaceArgument retainedArgument parameters surfaceArguments
      retainedArguments retainedConstants parameter argument tail argumentIH tailIH
      groundTypes groundConstants typesGrounded constantsGrounded
    cases argumentGrounded : retainedArgument.instantiate substitution with
    | none => simp [Static.instantiateTypes, argumentGrounded] at typesGrounded
    | some groundArgument =>
        cases tailGrounded : Static.instantiateTypes substitution retainedArguments with
        | none =>
            simp [Static.instantiateTypes, argumentGrounded, tailGrounded]
              at typesGrounded
        | some groundArguments =>
            simp [Static.instantiateTypes, argumentGrounded, tailGrounded]
              at typesGrounded
            subst groundTypes
            exact .typeParameter (argumentIH groundArgument argumentGrounded)
              (tailIH groundArguments groundConstants tailGrounded constantsGrounded)
  · intro surfaceArgument retainedArgument parameters surfaceArguments
      retainedArguments retainedConstants parameter argument tail argumentIH tailIH
      groundTypes groundConstants typesGrounded constantsGrounded
    cases argumentGrounded : retainedArgument.instantiate substitution with
    | none =>
        simp [Static.instantiateConstants, argumentGrounded] at constantsGrounded
    | some groundArgument =>
        cases tailGrounded : Static.instantiateConstants substitution
          retainedConstants with
        | none =>
            simp [Static.instantiateConstants, argumentGrounded, tailGrounded]
              at constantsGrounded
        | some groundArguments =>
            simp [Static.instantiateConstants, argumentGrounded, tailGrounded]
              at constantsGrounded
            subst groundConstants
            exact .constParameter (argumentIH groundArgument argumentGrounded)
              (tailIH groundTypes groundArguments typesGrounded tailGrounded)

/-- The source return annotation/default and its ground return type are one
    specialization fact. This prevents monomorphic body lowering from choosing
    a return interpretation independently of declaration-wide symbolic typing. -/
theorem ReturnTypeRetains.specializes
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes substitution groundEnclosingReturn concrete)
    (retained : ReturnTypeRetains symbolic.globals functionName surfaceReturn
      symbolicReturn)
    (grounded : symbolicReturn.instantiate substitution = some groundReturn) :
    ReturnTypeGrounds concrete functionName surfaceReturn groundReturn := by
  cases retained with
  | mainDefault main =>
      simp [Static.Ty.instantiate] at grounded
      subst groundReturn
      exact .mainDefault main
  | unitDefault notMain =>
      simp [Static.Ty.instantiate] at grounded
      subst groundReturn
      exact .unitDefault notMain
  | value retainedType =>
      exact .value (retainedType.specializes contexts grounded)

theorem ConstTypeArgumentRetains.specializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (retained : ConstTypeArgumentRetains symbolic.globals surface retainedConstant)
    (grounded : retainedConstant.instantiate outer = some groundConstant) :
    SurfaceElaboration.ConstTypeArgumentGrounds concrete surface groundConstant := by
  cases retained with
  | parameter single resolved =>
      exact .parameter single (contexts.resolvesConstParameter resolved)
        (by simpa [Static.Const.instantiate, contexts.substitution] using grounded)

inductive GenericArgumentsRetain
    (context : SurfaceElaboration.Context)
    (substitution : Static.SymbolicSubstitution) :
    List Static.GenericParameter → List Surface.TypeExpr → Prop where
  | nil : GenericArgumentsRetain context substitution [] []
  | typeParameter
      (argument : TypeRetains context surfaceArgument retainedArgument)
      (bound : substitution.types parameter = some retainedArgument)
      (tail : GenericArgumentsRetain context substitution parameters surfaceArguments) :
      GenericArgumentsRetain context substitution
        (.typeParameter parameter :: parameters)
        (surfaceArgument :: surfaceArguments)
  | constParameter
      (argument : ConstTypeArgumentRetains context surfaceArgument retainedArgument)
      (bound : substitution.constants parameter = some retainedArgument)
      (tail : GenericArgumentsRetain context substitution parameters surfaceArguments) :
      GenericArgumentsRetain context substitution
        (.constParameter parameter :: parameters)
        (surfaceArgument :: surfaceArguments)

theorem GenericArgumentsRetain.specializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (retained : GenericArgumentsRetain symbolic.globals symbolicSubstitution
      parameters surfaceArguments)
    (grounded : Static.SymbolicParametersGround outer symbolicSubstitution
      parameters) :
    SurfaceElaboration.GenericArgumentsGround concrete
      (symbolicSubstitution.composeGround outer) parameters surfaceArguments := by
  induction retained with
  | nil => exact .nil
  | @typeParameter surfaceArgument retainedArgument parameters surfaceArguments
      parameter argument bound tail tailIH =>
      cases grounded with
      | typeParameter symbolicFound argumentGrounded groundedTail =>
          rw [bound] at symbolicFound
          have argumentEquality := Option.some.inj symbolicFound
          subst retainedArgument
          exact .typeParameter
            (argument.specializes contexts argumentGrounded)
            (by simpa [Static.SymbolicSubstitution.composeGround, bound] using
              argumentGrounded)
            (tailIH groundedTail)
  | @constParameter surfaceArgument retainedArgument parameters surfaceArguments
      parameter argument bound tail tailIH =>
      cases grounded with
      | constParameter symbolicFound argumentGrounded groundedTail =>
          rw [bound] at symbolicFound
          have argumentEquality := Option.some.inj symbolicFound
          subst retainedArgument
          exact .constParameter
            (argument.specializes contexts argumentGrounded)
            (by simpa [Static.SymbolicSubstitution.composeGround, bound] using
              argumentGrounded)
            (tailIH groundedTail)

def ExplicitGenericArgumentsRetain
    (context : SurfaceElaboration.Context) (path : Surface.Path)
    (parameters : List Static.GenericParameter)
    (substitution : Static.SymbolicSubstitution) : Prop :=
  ∃ head tail,
    SurfaceElaboration.pathTypeArguments? path = some (head :: tail) ∧
      GenericArgumentsRetain context substitution parameters (head :: tail)

theorem ExplicitGenericArgumentsRetain.excludesNoGenericArguments
    (explicit : ExplicitGenericArgumentsRetain context path parameters substitution)
    (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path) : False := by
  obtain ⟨head, tail, explicitFound, _arguments⟩ := explicit
  have impossible := Option.some.inj (explicitFound.symm.trans implicitArguments)
  cases impossible

theorem ExplicitGenericArgumentsRetain.specializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (retained : ExplicitGenericArgumentsRetain symbolic.globals path parameters
      symbolicSubstitution)
    (grounded : Static.SymbolicParametersGround outer symbolicSubstitution
      parameters) :
    SurfaceElaboration.ExplicitNominalArgumentsGround concrete path parameters
      (symbolicSubstitution.composeGround outer) := by
  obtain ⟨head, tail, found, arguments⟩ := retained
  exact ⟨head, tail, found, arguments.specializes contexts grounded⟩

def SymbolicPathArgumentsCompatible
    (context : SurfaceElaboration.Context) (path : Surface.Path)
    (parameters : List Static.GenericParameter)
    (substitution : Static.SymbolicSubstitution) : Prop :=
  SurfaceElaboration.PathHasNoGenericArguments path ∨
    ExplicitGenericArgumentsRetain context path parameters substitution

theorem SymbolicPathArgumentsCompatible.specializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (compatible : SymbolicPathArgumentsCompatible symbolic.globals path parameters
      symbolicSubstitution)
    (grounded : Static.SymbolicParametersGround outer symbolicSubstitution
      parameters) :
    SurfaceElaboration.NominalPathArgumentsCompatible concrete path parameters
      (symbolicSubstitution.composeGround outer) := by
  rcases compatible with implicit | explicit
  · exact Or.inl implicit
  · exact Or.inr (explicit.specializes contexts grounded)

/-- Enum variants inhabit the value namespace, so symbolic lookup must honor
    lexical shadowing just as concrete lowering does. Constructor metadata is
    still selected from the shared global table. -/
def SelectsSymbolicVariantConstructor
    (context : SymbolicBodyContext) (path : Surface.Path)
    (selected : SurfaceElaboration.VariantConstructorScheme) : Prop :=
  SourceWellFormed.GlobalPathNotShadowed context.scopeContext path ∧
    SurfaceElaboration.SelectsVariantConstructor context.globals path selected

theorem SymbolicBodyContext.Specializes.selectsVariantConstructor
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes outer groundReturnType concrete)
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor) :
    SurfaceElaboration.SelectsVariantConstructor concrete path constructor := by
  rcases selected with ⟨notShadowed,
    _globalNotShadowed, symbol, resolved, member, declaration, unique⟩
  refine ⟨specialized.globalPathNotShadowed notShadowed, symbol,
    specialized.resolvesGlobal resolved, ?_, declaration, ?_⟩
  · rw [specialized.globals]
    exact member
  · intro candidate candidateMember candidateDeclaration
    have globalCandidateMember : candidate ∈ symbolic.globals.variantConstructors := by
      rw [specialized.globals] at candidateMember
      exact candidateMember
    exact unique candidate globalCandidateMember candidateDeclaration

/-- Lexical source selection and one finite layout row determine the concrete
    variant selected by pattern lowering. This theorem also preserves the
    value-namespace shadowing decision made before monomorphization. -/
theorem VariantArtifactDemand.selectsVariant
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
    (demand : VariantArtifactDemand concrete constructor groundReceiver
      groundPayload entry) :
    SurfaceElaboration.SelectsVariant concrete groundReceiver path entry := by
  have concreteConstructor := contexts.selectsVariantConstructor selected
  rcases concreteConstructor with
    ⟨notShadowed, symbol, resolved, constructorMember,
      constructorDeclaration, constructorUnique⟩
  cases demand with
  | intro entryMember entryDeclaration entryReceiver entryVariant entryPayload
      entryUnique =>
      refine ⟨notShadowed, symbol, resolved, entryMember,
        entryDeclaration.trans constructorDeclaration, entryReceiver, ?_⟩
      intro candidate candidateMember candidateDeclaration candidateReceiver
      exact entryUnique candidate candidateMember
        (candidateDeclaration.trans constructorDeclaration.symm)
        candidateReceiver

theorem SymbolicBodyContext.Specializes.selectsStructConstructor
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes outer groundReturnType concrete)
    (selected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path constructor) :
    SurfaceElaboration.SelectsStructConstructor concrete path constructor := by
  rcases selected with ⟨symbol, resolved, member, declaration, unique⟩
  refine ⟨symbol, specialized.resolvesGlobal resolved, ?_, declaration, ?_⟩
  · rw [specialized.globals]
    exact member
  · intro candidate candidateMember candidateDeclaration
    have globalCandidateMember : candidate ∈ symbolic.globals.structConstructors := by
      rw [specialized.globals] at candidateMember
      exact candidateMember
    exact unique candidate globalCandidateMember candidateDeclaration

def SymbolicMemberBase : Static.Ty → Static.Ty → Prop
  | .reference referent, receiver => referent = receiver
  | receiver, selected => receiver = selected

/-- Symbolic member normalization removes at most the language-defined
    immutable reference layer and therefore determines one receiver type. -/
theorem SymbolicMemberBase.unique
    (left : SymbolicMemberBase source leftReceiver)
    (right : SymbolicMemberBase source rightReceiver) :
    leftReceiver = rightReceiver := by
  cases source <;> simp [SymbolicMemberBase] at left right <;> simp_all

def SelectsSymbolicField
    (context : SymbolicBodyContext) (receiver : Static.Ty)
    (name : Surface.Name) (result : Static.Ty) : Prop :=
  ∃ sourceType typeArguments constArguments constructor substitution field,
    receiver = .nominal sourceType typeArguments constArguments ∧
    constructor ∈ context.globals.structConstructors ∧
    constructor.sourceType = sourceType ∧
    Static.SymbolicArgumentsBound substitution constructor.genericParameters
      typeArguments constArguments ∧
    field ∈ constructor.fields ∧ field.name = name ∧
    field.type.substitute substitution = some result ∧
    ∀ candidate,
      candidate ∈ constructor.fields → candidate.name = name → candidate = field

/-- Signature applicability used to choose the visibility tier for an inferred
    member call. Membership is kept outside the predicate because
    `MethodScheme.preferredAt` owns the finite declaration table. -/
def SymbolicMethodLookupApplicable
    (context : SymbolicBodyContext) (receiver : Static.Ty)
    (name : Surface.Name) (scheme : Static.MethodScheme) : Prop :=
  ∃ substitution,
    scheme.name = name ∧
    Static.TySymbolicallyMatches substitution scheme.receiverType receiver ∧
    Static.SymbolicParametersBound substitution scheme.genericParameters ∧
    Static.SymbolicRequirementsSatisfied context.globals.implementations
      context.assumptions substitution scheme.requirements

def SelectsSymbolicMethod
    (context : SymbolicBodyContext) (receiver : Static.Ty)
    (name : Surface.Name) (argumentTypes : List Static.Ty)
    (result : Static.Ty) : Prop :=
  ∃ scheme substitution,
    scheme ∈ context.globals.methods ∧ scheme.name = name ∧
    scheme.receiverMode ≠ .none ∧
    Static.TySymbolicallyMatches substitution scheme.receiverType receiver ∧
    Static.TypesSymbolicallyMatch substitution scheme.argumentTypes argumentTypes ∧
    SurfaceElaboration.TypesDetermineGenericParameters
      (scheme.receiverType :: scheme.argumentTypes) scheme.genericParameters ∧
    Static.SymbolicParametersBound substitution scheme.genericParameters ∧
    Static.SymbolicRequirementsSatisfied context.globals.implementations
      context.assumptions substitution
      scheme.requirements ∧
    scheme.returnType.substitute substitution = some result ∧
    scheme.preferredAt context.globals.methods context.globals.currentModule
      (SymbolicMethodLookupApplicable context receiver name) ∧
    ∀ candidate,
      candidate ∈ context.globals.methods →
      SymbolicMethodLookupApplicable context receiver name candidate →
      candidate.preferredAt context.globals.methods context.globals.currentModule
        (SymbolicMethodLookupApplicable context receiver name) →
      candidate.declaration = scheme.declaration

/-- Contextual argument checking is available after receiver and member name
    select one symbolic method signature without consulting argument-expression
    defaults. Ordinary argument types never participate in method lookup;
    contextual literals therefore cannot choose among declarations. -/
def SymbolicMethodSignatureApplies
    (context : SymbolicBodyContext) (receiver : Static.Ty)
    (name : Surface.Name) (scheme : Static.MethodScheme)
    (substitution : Static.SymbolicSubstitution)
    (argumentTypes : List Static.Ty) (result : Static.Ty) : Prop :=
  scheme ∈ context.globals.methods ∧
  scheme.name = name ∧
  scheme.receiverMode ≠ .none ∧
  Static.TySymbolicallyMatches substitution scheme.receiverType receiver ∧
  Static.SymbolicParametersBound substitution scheme.genericParameters ∧
  Static.SymbolicRequirementsSatisfied context.globals.implementations
    context.assumptions substitution scheme.requirements ∧
  Static.substituteTypes substitution scheme.argumentTypes = some argumentTypes ∧
  scheme.returnType.substitute substitution = some result

def SelectsContextualSymbolicMethod
    (context : SymbolicBodyContext) (receiver : Static.Ty)
    (name : Surface.Name) (scheme : Static.MethodScheme)
    (substitution : Static.SymbolicSubstitution)
    (argumentTypes : List Static.Ty) (result : Static.Ty) : Prop :=
  SymbolicMethodSignatureApplies context receiver name scheme substitution
    argumentTypes result ∧
  scheme.preferredAt context.globals.methods context.globals.currentModule
    (SymbolicMethodLookupApplicable context receiver name) ∧
  SurfaceElaboration.TypesDetermineGenericParameters [scheme.receiverType]
    scheme.genericParameters ∧
  ∀ candidate,
    candidate ∈ context.globals.methods →
    SymbolicMethodLookupApplicable context receiver name candidate →
    candidate.preferredAt context.globals.methods context.globals.currentModule
      (SymbolicMethodLookupApplicable context receiver name) →
    candidate.declaration = scheme.declaration

/-- Symbolic selection for `Type::function(arguments)`. The owner type fixes
    the receiver key. Receiverless functions expose their complete parameter
    vector; explicit typed receivers expose the receiver type as the first
    ordinary parameter. The receiver/name declaration tier is shared with
    member lookup, matching the compiler's single inherent-function index. -/
def SelectsSymbolicAssociatedMethod
    (context : SymbolicBodyContext) (receiver : Static.Ty)
    (name : Surface.Name) (argumentTypes : List Static.Ty)
    (result : Static.Ty) : Prop :=
  ∃ scheme substitution parameterTypes,
    scheme ∈ context.globals.methods ∧ scheme.name = name ∧
    scheme.associatedArgumentTypes? = some parameterTypes ∧
    Static.TySymbolicallyMatches substitution scheme.receiverType receiver ∧
    Static.TypesSymbolicallyMatch substitution parameterTypes argumentTypes ∧
    SurfaceElaboration.TypesDetermineGenericParameters
      (scheme.receiverType :: scheme.argumentTypes) scheme.genericParameters ∧
    Static.SymbolicParametersBound substitution scheme.genericParameters ∧
    Static.SymbolicRequirementsSatisfied context.globals.implementations
      context.assumptions substitution scheme.requirements ∧
    scheme.returnType.substitute substitution = some result ∧
    scheme.preferredAt context.globals.methods context.globals.currentModule
      (SymbolicMethodLookupApplicable context receiver name) ∧
    ∀ candidate,
      candidate ∈ context.globals.methods →
      SymbolicMethodLookupApplicable context receiver name candidate →
      candidate.preferredAt context.globals.methods context.globals.currentModule
        (SymbolicMethodLookupApplicable context receiver name) →
      candidate.declaration = scheme.declaration

/-- Contextual associated-call selection fixes the declaration from the owner
    type before checking arguments against its substituted source parameter
    vector. -/
def SelectsContextualSymbolicAssociatedMethod
    (context : SymbolicBodyContext) (receiver : Static.Ty)
    (name : Surface.Name) (scheme : Static.MethodScheme)
    (substitution : Static.SymbolicSubstitution)
    (argumentTypes : List Static.Ty) (result : Static.Ty) : Prop :=
  ∃ parameterTypes,
    scheme ∈ context.globals.methods ∧
    scheme.name = name ∧
    scheme.associatedArgumentTypes? = some parameterTypes ∧
    Static.TySymbolicallyMatches substitution scheme.receiverType receiver ∧
    Static.SymbolicParametersBound substitution scheme.genericParameters ∧
    Static.SymbolicRequirementsSatisfied context.globals.implementations
      context.assumptions substitution scheme.requirements ∧
    Static.substituteTypes substitution parameterTypes = some argumentTypes ∧
    scheme.returnType.substitute substitution = some result ∧
    scheme.preferredAt context.globals.methods context.globals.currentModule
      (SymbolicMethodLookupApplicable context receiver name) ∧
    SurfaceElaboration.TypesDetermineGenericParameters [scheme.receiverType]
      scheme.genericParameters ∧
    ∀ candidate,
      candidate ∈ context.globals.methods →
      SymbolicMethodLookupApplicable context receiver name candidate →
      candidate.preferredAt context.globals.methods context.globals.currentModule
        (SymbolicMethodLookupApplicable context receiver name) →
      candidate.declaration = scheme.declaration

inductive SymbolicUnaryHasType :
    Surface.UnaryOp → Static.Ty → Static.Ty → Prop where
  | scalar
      (typed : Typing.UnaryOpHasType (SurfaceElaboration.lowerUnaryOp op)
        (.scalar input) (.scalar output)) :
      SymbolicUnaryHasType op (.scalar input) (.scalar output)

inductive SymbolicBinaryHasType :
    Surface.BinaryOp → Static.Ty → Static.Ty → Static.Ty → Prop where
  | exact
      (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
        (.scalar left) (.scalar right) (.scalar output)) :
      SymbolicBinaryHasType op (.scalar left) (.scalar right) (.scalar output)
  | rightCast
      (different : right ≠ left)
      (notPreferred : ¬ Typing.RightDominatesBinary left right)
      (conversion : Typing.ScalarCast right left)
      (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
        (.scalar left) (.scalar left) (.scalar output)) :
      SymbolicBinaryHasType op (.scalar left) (.scalar right) (.scalar output)
  | leftCast
      (preferred : Typing.RightDominatesBinary left right)
      (conversion : Typing.ScalarCast left right)
      (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
        (.scalar right) (.scalar right) (.scalar output)) :
      SymbolicBinaryHasType op (.scalar left) (.scalar right) (.scalar output)

/-- For fixed symbolic operand types, the coercion policy and core operator
    typing determine one result type. Exact, right-cast, and left-cast modes
    are pairwise disjoint except where their outputs already coincide. -/
theorem SymbolicBinaryHasType.output_unique
    (left : SymbolicBinaryHasType op leftType rightType leftOutput)
    (right : SymbolicBinaryHasType op leftType rightType rightOutput) :
    leftOutput = rightOutput := by
  cases left with
  | exact leftTyped =>
      cases right with
      | exact rightTyped =>
          have outputEquality := leftTyped.output_unique rightTyped
          injection outputEquality with scalarEquality
          cases scalarEquality
          rfl
      | rightCast different notPreferred conversion rightTyped =>
          cases op <;> cases leftTyped <;> cases conversion <;> simp_all
      | leftCast preferred conversion rightTyped =>
          cases op <;> cases leftTyped <;> cases conversion <;> simp_all <;>
            cases preferred
  | rightCast different notPreferred conversion leftTyped =>
      cases right with
      | exact rightTyped =>
          cases op <;> cases rightTyped <;> cases conversion <;> simp_all
      | rightCast rightDifferent rightNotPreferred rightConversion rightTyped =>
          have outputEquality := leftTyped.output_unique rightTyped
          injection outputEquality with scalarEquality
          cases scalarEquality
          rfl
      | leftCast preferred rightConversion rightTyped =>
          exact (notPreferred preferred).elim
  | leftCast preferred conversion leftTyped =>
      cases right with
      | exact rightTyped =>
          cases op <;> cases rightTyped <;> cases conversion <;> simp_all <;>
            cases preferred
      | rightCast rightDifferent notPreferred rightConversion rightTyped =>
          exact (notPreferred preferred).elim
      | leftCast rightPreferred rightConversion rightTyped =>
          have outputEquality := leftTyped.output_unique rightTyped
          injection outputEquality with scalarEquality
          cases scalarEquality
          rfl

/-- The ordinary scalar-binary coercion decision paired with the exact core
    expression it emits. Contextual null-pointer literals are separate because
    they do not first infer an ordinary operand type. -/
inductive BinaryOperationSpecializes
    (op : Surface.BinaryOp) (left right : Core.ScalarTy)
    (coreLeft coreRight : Core.Expr) : Core.ScalarTy → Core.Expr → Prop where
  | exact
      (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
        (.scalar left) (.scalar right) (.scalar output)) :
      BinaryOperationSpecializes op left right coreLeft coreRight
        output
        (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft coreRight)
  | rightCast
      (different : right ≠ left)
      (notPreferred : ¬ Typing.RightDominatesBinary left right)
      (conversion : Typing.ScalarCast right left)
      (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
        (.scalar left) (.scalar left) (.scalar output)) :
      BinaryOperationSpecializes op left right coreLeft coreRight
        output
        (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft
          (.cast left coreRight))
  | leftCast
      (preferred : Typing.RightDominatesBinary left right)
      (conversion : Typing.ScalarCast left right)
      (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
        (.scalar right) (.scalar right) (.scalar output)) :
      BinaryOperationSpecializes op left right coreLeft coreRight
        output
        (.binary (SurfaceElaboration.lowerBinaryOp op) (.cast right coreLeft)
          coreRight)

/-- An ordinary scalar-binary occurrence has one result type and one emitted
    core expression. -/
theorem BinaryOperationSpecializes.unique
    (left : BinaryOperationSpecializes op leftType rightType coreLeft coreRight
      leftOutput leftCore)
    (right : BinaryOperationSpecializes op leftType rightType coreLeft coreRight
      rightOutput rightCore) :
    leftOutput = rightOutput ∧ leftCore = rightCore := by
  cases left with
  | exact leftTyped =>
      cases right with
      | exact rightTyped =>
          have outputEquality := leftTyped.output_unique rightTyped
          injection outputEquality with scalarEquality
          exact ⟨scalarEquality, rfl⟩
      | rightCast different notPreferred conversion rightTyped =>
          cases op <;> cases leftTyped <;> cases conversion <;> simp_all
      | leftCast preferred conversion rightTyped =>
          cases op <;> cases leftTyped <;> cases conversion <;> simp_all <;>
            cases preferred
  | rightCast different notPreferred conversion leftTyped =>
      cases right with
      | exact rightTyped =>
          cases op <;> cases rightTyped <;> cases conversion <;> simp_all
      | rightCast rightDifferent rightNotPreferred rightConversion rightTyped =>
          have outputEquality := leftTyped.output_unique rightTyped
          injection outputEquality with scalarEquality
          exact ⟨scalarEquality, rfl⟩
      | leftCast preferred rightConversion rightTyped =>
          exact (notPreferred preferred).elim
  | leftCast preferred conversion leftTyped =>
      cases right with
      | exact rightTyped =>
          cases op <;> cases rightTyped <;> cases conversion <;> simp_all <;>
            cases preferred
      | rightCast rightDifferent notPreferred rightConversion rightTyped =>
          exact (notPreferred preferred).elim
      | leftCast rightPreferred rightConversion rightTyped =>
          have outputEquality := leftTyped.output_unique rightTyped
          injection outputEquality with scalarEquality
          exact ⟨scalarEquality, rfl⟩

private theorem noArithmeticRawPointer
    (typed : Typing.ArithmeticTy (.scalar .rawPtr)) : False := by
  cases typed

private theorem noRawPointerOffset
    (typed : Typing.PointerOffsetTy (.scalar .rawPtr)) : False := by
  cases typed

/-- An ordinary `ptr op i32` typing derivation and a contextual `ptr op ptr`
    null derivation cannot describe the same operator occurrence. Pointer
    arithmetic admits only the former; pointer equality admits only the latter.
    This is a type-level disjointness fact and deliberately does not mention the
    Core expressions emitted after the decision. -/
theorem SymbolicBinaryHasType.incompatible_with_null_right
    (ordinary : SymbolicBinaryHasType op (.scalar .rawPtr)
      (.scalar (.signed .i32)) ordinaryOutput)
    (nullTyped : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar .rawPtr) (.scalar .rawPtr) nullOutput) : False := by
  cases ordinary with
  | exact ordinaryTyped =>
      cases op <;> cases ordinaryTyped <;> cases nullTyped
      all_goals solve_by_elim [noArithmeticRawPointer, noRawPointerOffset]
  | rightCast different notPreferred conversion ordinaryTyped =>
      cases conversion
  | leftCast preferred conversion ordinaryTyped =>
      cases conversion

/-- The symmetric contextual-null case is disjoint for the same reason. -/
theorem SymbolicBinaryHasType.incompatible_with_null_left
    (ordinary : SymbolicBinaryHasType op (.scalar (.signed .i32))
      (.scalar .rawPtr) ordinaryOutput)
    (nullTyped : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar .rawPtr) (.scalar .rawPtr) nullOutput) : False := by
  cases ordinary with
  | exact ordinaryTyped =>
      cases op <;> cases ordinaryTyped <;> cases nullTyped
      all_goals solve_by_elim [noArithmeticRawPointer, noRawPointerOffset]
  | rightCast different notPreferred conversion ordinaryTyped =>
      cases conversion
  | leftCast preferred conversion ordinaryTyped =>
      cases conversion

def SymbolicIntegerType : Static.Ty → Prop
  | .scalar type => Typing.IntegerTy (.scalar type)
  | _ => False

def literalDefaultScalar : Surface.Literal → Core.ScalarTy
  | .integer _ => .signed .i32
  | .float _ => .f32
  | .boolean _ => .bool
  | .character _ => .char
  | .string _ => .string

theorem literalDefaultType_eq_scalar (literal : Surface.Literal) :
    Elaboration.literalDefaultType literal = .scalar (literalDefaultScalar literal) := by
  cases literal <;> rfl

inductive LiteralInfersSymbolic
    (target : Core.Target) (literal : Surface.Literal) : Static.Ty → Prop where
  | default
      (lowered : Elaboration.LiteralElaborates target literal
        (Elaboration.literalDefaultType literal) coreExpression) :
      LiteralInfersSymbolic target literal
        (.scalar (literalDefaultScalar literal))

def LiteralChecksSymbolic
    (target : Core.Target) (literal : Surface.Literal)
    (type : Static.Ty) : Prop :=
  ∃ scalar coreExpression,
    type = .scalar scalar ∧
      Elaboration.LiteralElaborates target literal (.scalar scalar) coreExpression

inductive SymbolicAssignOpHasType :
    Surface.AssignOp → Static.Ty → Prop where
  | set : SymbolicAssignOpHasType .set type
  | scalar
      (typed : Typing.AssignOpHasType (SurfaceElaboration.lowerAssignOp op)
        (.scalar type)) :
      SymbolicAssignOpHasType op (.scalar type)

mutual
  inductive SymbolicExprInfers :
      SymbolicBodyContext → Surface.Expr → Static.Ty → Prop where
    | literal
        (inferred : LiteralInfersSymbolic context.globals.target literal type) :
        SymbolicExprInfers context (.literal literal) type
    | signedMinimumLiteral
        (lowered : ∃ expression,
          Elaboration.SignedMinimumLiteralElaborates
            context.globals.target text .i32 expression) :
        SymbolicExprInfers context
          (.unary .negative (.literal (.integer text)))
          (.scalar (.signed .i32))
    | local
        (single : SurfaceElaboration.singleNamePath? path = some name)
        (resolved : ResolvesSymbolicLocal context.locals name binding) :
        SymbolicExprInfers context (.path path) binding.type
    | selfValue
        (resolved : ResolvesSymbolicLocal context.locals "self" binding) :
        SymbolicExprInfers context .selfValue binding.type
    | constant
        (selected : SourceWellFormed.SelectsConstant
          context.scopeContext path entry) :
        SymbolicExprInfers context (.path path) entry.type.toTy
    | array
        (head : SymbolicExprInfers context surfaceHead elementType)
        (tail : SymbolicExprsCheck context surfaceTail
          (List.replicate surfaceTail.length elementType)) :
        SymbolicExprInfers context (.array (surfaceHead :: surfaceTail))
          (.array elementType (.literal (surfaceHead :: surfaceTail).length))
    | structExplicit
        (selected : SurfaceElaboration.SelectsStructConstructor
          context.globals path constructor)
        (explicit : ExplicitGenericArgumentsRetain context.globals path
          constructor.genericParameters substitution)
        (arguments : Static.SymbolicArgumentsBound substitution
          constructor.genericParameters typeArguments constArguments)
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution constructor.requirements)
        (fields : SymbolicStructFieldsCheck context substitution
          constructor.fields surfaceFields) :
        SymbolicExprInfers context (.structValue path surfaceFields)
          (.nominal constructor.sourceType typeArguments constArguments)
    | structInferred
        (selected : SurfaceElaboration.SelectsStructConstructor
          context.globals path constructor)
        (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
        (generic : constructor.genericParameters ≠ [])
        (determined : SurfaceElaboration.TypesDetermineGenericParameters
          (constructor.fields.map fun field => field.type)
          constructor.genericParameters)
        (fields : SymbolicStructFieldsInfer context substitution
          constructor.fields surfaceFields)
        (arguments : Static.SymbolicArgumentsBound substitution
          constructor.genericParameters typeArguments constArguments)
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution constructor.requirements) :
        SymbolicExprInfers context (.structValue path surfaceFields)
          (.nominal constructor.sourceType typeArguments constArguments)
    | structNongeneric
        (selected : SurfaceElaboration.SelectsStructConstructor
          context.globals path constructor)
        (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
        (nongeneric : constructor.genericParameters = [])
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution constructor.requirements)
        (fields : SymbolicStructFieldsCheck context substitution
          constructor.fields surfaceFields) :
        SymbolicExprInfers context (.structValue path surfaceFields)
          (.nominal constructor.sourceType [] [])
    | unary
        (operand : SymbolicExprInfers context surfaceOperand inputType)
        (typed : SymbolicUnaryHasType op inputType outputType) :
        SymbolicExprInfers context (.unary op surfaceOperand) outputType
    | binary
        (left : SymbolicExprInfers context surfaceLeft leftType)
        (right : SymbolicExprInfers context surfaceRight rightType)
        (typed : SymbolicBinaryHasType op leftType rightType outputType) :
        SymbolicExprInfers context
          (.binary op surfaceLeft surfaceRight) outputType
    | binaryNullPointerRight
        (left : SymbolicExprInfers context surfaceLeft (.scalar .rawPtr))
        (null : LiteralChecksSymbolic context.globals.target
          (.integer text) (.scalar .rawPtr))
        (typed : SymbolicBinaryHasType op (.scalar .rawPtr)
          (.scalar .rawPtr) outputType) :
        SymbolicExprInfers context
          (.binary op surfaceLeft (.literal (.integer text))) outputType
    | binaryNullPointerLeft
        (null : LiteralChecksSymbolic context.globals.target
          (.integer text) (.scalar .rawPtr))
        (right : SymbolicExprInfers context surfaceRight (.scalar .rawPtr))
        (typed : SymbolicBinaryHasType op (.scalar .rawPtr)
          (.scalar .rawPtr) outputType) :
        SymbolicExprInfers context
          (.binary op (.literal (.integer text)) surfaceRight) outputType
    | assign
        (place : SymbolicPlaceHasType context surfacePlace placeType)
        (value : SymbolicExprChecks context surfaceValue placeType)
        (typed : SymbolicAssignOpHasType op placeType) :
        SymbolicExprInfers context
          (.assign op surfacePlace surfaceValue) .unit
    | printI32
        (builtin : SurfaceElaboration.builtinIntrinsic? path = some .printI32)
        (argument : SymbolicExprChecks context surfaceArgument
          (.scalar (.signed .i32))) :
        SymbolicExprInfers context
          (.call (.path path) [surfaceArgument]) .unit
    | assert
        (builtin : SurfaceElaboration.builtinIntrinsic? path = some .assert)
        (argument : SymbolicExprChecks context surfaceArgument (.scalar .bool)) :
        SymbolicExprInfers context
          (.call (.path path) [surfaceArgument]) .unit
    | i32ArrayDataPtr
        (builtin : SurfaceElaboration.builtinIntrinsic? path =
          some .i32ArrayDataPtr)
        (argument : SymbolicExprChecks context surfaceArgument
          (.array (.scalar (.signed .i32)) length)) :
        SymbolicExprInfers context
          (.call (.path path) [surfaceArgument]) (.scalar .rawPtr)
    | directCallExplicit
        (selected : SourceWellFormed.SelectsFunction
          context.scopeContext path scheme)
        (explicit : ExplicitGenericArgumentsRetain context.globals path
          scheme.genericParameters substitution)
        (parameters : Static.substituteTypes substitution scheme.parameterTypes =
          some parameterTypes)
        (arguments : SymbolicExprsCheck context surfaceArguments parameterTypes)
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution scheme.requirements)
        (returned : scheme.returnType.substitute substitution = some returnType)
        (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
        SymbolicExprInfers context
          (.call (.path path) surfaceArguments) returnType
    | directCallInferred
        (selected : SourceWellFormed.SelectsFunction
          context.scopeContext path scheme)
        (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
        (generic : scheme.genericParameters ≠ [])
        (determined : SurfaceElaboration.TypesDetermineGenericParameters
          scheme.parameterTypes scheme.genericParameters)
        (arguments : SymbolicExprsInfer context surfaceArguments argumentTypes)
        (typeMatches : Static.TypesSymbolicallyMatch substitution
          scheme.parameterTypes argumentTypes)
        (bound : Static.SymbolicParametersBound substitution
          scheme.genericParameters)
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution scheme.requirements)
        (returned : scheme.returnType.substitute substitution = some returnType)
        (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
        SymbolicExprInfers context
          (.call (.path path) surfaceArguments) returnType
    | directCallNongeneric
        (selected : SourceWellFormed.SelectsFunction
          context.scopeContext path scheme)
        (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
        (nongeneric : scheme.genericParameters = [])
        (arguments : SymbolicExprsCheck context surfaceArguments
          scheme.parameterTypes)
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution scheme.requirements)
        (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
        SymbolicExprInfers context
          (.call (.path path) surfaceArguments) scheme.returnType
    | associatedCall
        (split : SurfaceElaboration.associatedFunctionPath? path =
          some (ownerPath, name))
        (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
        (notFunction : ¬ ∃ scheme,
          SourceWellFormed.SelectsFunction context.scopeContext path scheme)
        (notVariant : ¬ ∃ constructor,
          SelectsSymbolicVariantConstructor context path constructor)
        (owner : TypeRetains context.globals (.path ownerPath.segments)
          receiverType)
        (arguments : SymbolicExprsInfer context surfaceArguments argumentTypes)
        (selected : SelectsSymbolicAssociatedMethod context receiverType name
          argumentTypes returnType) :
        SymbolicExprInfers context (.call (.path path) surfaceArguments) returnType
    | associatedCallContextual
        (split : SurfaceElaboration.associatedFunctionPath? path =
          some (ownerPath, name))
        (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
        (notFunction : ¬ ∃ scheme,
          SourceWellFormed.SelectsFunction context.scopeContext path scheme)
        (notVariant : ¬ ∃ constructor,
          SelectsSymbolicVariantConstructor context path constructor)
        (owner : TypeRetains context.globals (.path ownerPath.segments)
          receiverType)
        (selected : SelectsContextualSymbolicAssociatedMethod context receiverType
          name scheme substitution expectedArgumentTypes returnType)
        (arguments : SymbolicExprsCheck context surfaceArguments
          expectedArgumentTypes) :
        SymbolicExprInfers context (.call (.path path) surfaceArguments) returnType
    | variantExplicit
        (selected : SelectsSymbolicVariantConstructor context path constructor)
        (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
        (explicit : ExplicitGenericArgumentsRetain context.globals path
          constructor.genericParameters substitution)
        (argumentsBound : Static.SymbolicArgumentsBound substitution
          constructor.genericParameters typeArguments constArguments)
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution constructor.requirements)
        (payload : SymbolicExprsSubstitutedCheck context substitution
          surfaceArguments constructor.payload) :
        SymbolicExprInfers context (.call (.path path) surfaceArguments)
          (.nominal constructor.sourceType typeArguments constArguments)
    | variantInferred
        (selected : SelectsSymbolicVariantConstructor context path constructor)
        (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
        (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
        (generic : constructor.genericParameters ≠ [])
        (determined : SurfaceElaboration.TypesDetermineGenericParameters
          constructor.payload constructor.genericParameters)
        (payload : SymbolicExprsInfer context surfaceArguments argumentTypes)
        (typeMatches : Static.TypesSymbolicallyMatch substitution
          constructor.payload argumentTypes)
        (argumentsBound : Static.SymbolicArgumentsBound substitution
          constructor.genericParameters typeArguments constArguments)
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution constructor.requirements) :
        SymbolicExprInfers context (.call (.path path) surfaceArguments)
          (.nominal constructor.sourceType typeArguments constArguments)
    | variantNongeneric
        (selected : SelectsSymbolicVariantConstructor context path constructor)
        (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
        (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
        (nongeneric : constructor.genericParameters = [])
        (payload : SymbolicExprsSubstitutedCheck context substitution
          surfaceArguments constructor.payload)
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution constructor.requirements) :
        SymbolicExprInfers context (.call (.path path) surfaceArguments)
          (.nominal constructor.sourceType [] [])
    | methodCall
        (receiver : SymbolicExprInfers context surfaceReceiver sourceReceiver)
        (memberBase : SymbolicMemberBase sourceReceiver receiverType)
        (arguments : SymbolicExprsInfer context surfaceArguments argumentTypes)
        (selected : SelectsSymbolicMethod context receiverType name
          argumentTypes returnType) :
        SymbolicExprInfers context
          (.call (.member surfaceReceiver name) surfaceArguments) returnType
    | methodCallContextual
        (receiver : SymbolicExprInfers context surfaceReceiver sourceReceiver)
        (memberBase : SymbolicMemberBase sourceReceiver receiverType)
        (selected : SelectsContextualSymbolicMethod context receiverType name
          scheme substitution expectedArgumentTypes returnType)
        (arguments : SymbolicExprsCheck context surfaceArguments
          expectedArgumentTypes) :
        SymbolicExprInfers context
          (.call (.member surfaceReceiver name) surfaceArguments) returnType
    | indexArray
        (base : SymbolicExprInfers context surfaceBase
          (.array elementType length))
        (index : SymbolicExprInfers context surfaceIndex indexType)
        (integer : SymbolicIntegerType indexType) :
        SymbolicExprInfers context (.index surfaceBase surfaceIndex) elementType
    | indexSlice
        (base : SymbolicExprInfers context surfaceBase (.slice elementType))
        (index : SymbolicExprInfers context surfaceIndex indexType)
        (integer : SymbolicIntegerType indexType) :
        SymbolicExprInfers context (.index surfaceBase surfaceIndex) elementType
    | field
        (base : SymbolicExprInfers context surfaceBase sourceReceiver)
        (memberBase : SymbolicMemberBase sourceReceiver receiverType)
        (selected : SelectsSymbolicField context receiverType name fieldType) :
        SymbolicExprInfers context (.member surfaceBase name) fieldType
    | matchValue
        (scrutinee : SymbolicExprInfers context surfaceScrutinee scrutineeType)
        (arms : SymbolicMatchArmsInfer context scrutineeType resultType surfaceArms) :
        SymbolicExprInfers context
          (.matchValue surfaceScrutinee surfaceArms) resultType

  inductive SymbolicExprChecks :
      SymbolicBodyContext → Surface.Expr → Static.Ty → Prop where
    | exact (inferred : SymbolicExprInfers context surfaceExpression type) :
        SymbolicExprChecks context surfaceExpression type
    | literal
        (checked : LiteralChecksSymbolic context.globals.target literal type) :
        SymbolicExprChecks context (.literal literal) type
    | signedMinimumLiteral
        (signed : type = .scalar (.signed signedType))
        (checked : ∃ expression,
          Elaboration.SignedMinimumLiteralElaborates
            context.globals.target text signedType expression) :
        SymbolicExprChecks context
          (.unary .negative (.literal (.integer text))) type
    | unaryLiteral
        (scalar : type = .scalar scalarType)
        (literal : ∃ expression,
          Elaboration.LiteralElaborates context.globals.target surfaceLiteral
            (.scalar scalarType) expression)
        (typed : Typing.UnaryOpHasType (SurfaceElaboration.lowerUnaryOp op)
          (.scalar scalarType) (.scalar scalarType)) :
        SymbolicExprChecks context
          (.unary op (.literal surfaceLiteral)) type
    | array
        (elements : SymbolicExprsCheck context surfaceElements
          (List.replicate surfaceElements.length elementType)) :
        SymbolicExprChecks context (.array surfaceElements)
          (.array elementType (.literal surfaceElements.length))
    | scalarCast
        (inferred : SymbolicExprInfers context surfaceExpression
          (.scalar sourceType))
        (notContextualLiteral : ¬ SurfaceElaboration.ContextualScalarLiteralApplies
          context.globals.target surfaceExpression targetType)
        (different : sourceType ≠ targetType)
        (conversion : Typing.ScalarCast sourceType targetType) :
        SymbolicExprChecks context surfaceExpression (.scalar targetType)
    | arrayToSlice
        (array : SymbolicExprInfers context surfaceExpression
          (.array elementType length)) :
        SymbolicExprChecks context surfaceExpression (.slice elementType)
    | structValue
        (selected : SurfaceElaboration.SelectsStructConstructor
          context.globals path constructor)
        (expected : type = .nominal constructor.sourceType
          typeArguments constArguments)
        (arguments : Static.SymbolicArgumentsBound substitution
          constructor.genericParameters typeArguments constArguments)
        (pathArguments : SymbolicPathArgumentsCompatible context.globals path
          constructor.genericParameters substitution)
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution constructor.requirements)
        (fields : SymbolicStructFieldsCheck context substitution
          constructor.fields surfaceFields) :
        SymbolicExprChecks context (.structValue path surfaceFields) type
    | variantCall
        (selected : SelectsSymbolicVariantConstructor context path constructor)
        (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
        (expected : type = .nominal constructor.sourceType
          typeArguments constArguments)
        (arguments : Static.SymbolicArgumentsBound substitution
          constructor.genericParameters typeArguments constArguments)
        (pathArguments : SymbolicPathArgumentsCompatible context.globals path
          constructor.genericParameters substitution)
        (requirements : Static.SymbolicRequirementsSatisfied
          context.globals.implementations context.assumptions
          substitution constructor.requirements)
        (payload : SymbolicExprsSubstitutedCheck context substitution
          surfaceArguments constructor.payload) :
        SymbolicExprChecks context (.call (.path path) surfaceArguments) type

  inductive SymbolicExprsInfer :
      SymbolicBodyContext → List Surface.Expr → List Static.Ty → Prop where
    | nil : SymbolicExprsInfer context [] []
    | cons
        (head : SymbolicExprInfers context surfaceHead headType)
        (tail : SymbolicExprsInfer context surfaceTail tailTypes) :
        SymbolicExprsInfer context (surfaceHead :: surfaceTail)
          (headType :: tailTypes)

  inductive SymbolicExprsCheck :
      SymbolicBodyContext → List Surface.Expr → List Static.Ty → Prop where
    | nil : SymbolicExprsCheck context [] []
    | cons
        (head : SymbolicExprChecks context surfaceHead headType)
        (tail : SymbolicExprsCheck context surfaceTail tailTypes) :
        SymbolicExprsCheck context (surfaceHead :: surfaceTail)
          (headType :: tailTypes)

  inductive SymbolicExprsSubstitutedCheck :
      SymbolicBodyContext → Static.SymbolicSubstitution →
        List Surface.Expr → List Static.Ty → Prop where
    | nil : SymbolicExprsSubstitutedCheck context substitution [] []
    | cons
        (instantiated : symbolicType.substitute substitution = some expectedType)
        (head : SymbolicExprChecks context surfaceHead expectedType)
        (tail : SymbolicExprsSubstitutedCheck context substitution
          surfaceTail symbolicTail) :
        SymbolicExprsSubstitutedCheck context substitution
          (surfaceHead :: surfaceTail) (symbolicType :: symbolicTail)

  inductive SymbolicStructFieldsCheck :
      SymbolicBodyContext → Static.SymbolicSubstitution →
        List SurfaceElaboration.StructFieldScheme →
        List (Surface.Name × Surface.Expr) → Prop where
    | nil : SymbolicStructFieldsCheck context substitution [] []
    | cons
        (removed : SurfaceElaboration.RemovesNamedField field.name
          surfaceFields surfaceValue remainder)
        (instantiated : field.type.substitute substitution = some expectedType)
        (value : SymbolicExprChecks context surfaceValue expectedType)
        (tail : SymbolicStructFieldsCheck context substitution
          fieldTail remainder) :
        SymbolicStructFieldsCheck context substitution
          (field :: fieldTail) surfaceFields

  inductive SymbolicStructFieldsInfer :
      SymbolicBodyContext → Static.SymbolicSubstitution →
        List SurfaceElaboration.StructFieldScheme →
        List (Surface.Name × Surface.Expr) → Prop where
    | nil : SymbolicStructFieldsInfer context substitution [] []
    | cons
        (removed : SurfaceElaboration.RemovesNamedField field.name
          surfaceFields surfaceValue remainder)
        (value : SymbolicExprInfers context surfaceValue actualType)
        (typeMatches : Static.TySymbolicallyMatches substitution field.type actualType)
        (tail : SymbolicStructFieldsInfer context substitution
          fieldTail remainder) :
        SymbolicStructFieldsInfer context substitution
          (field :: fieldTail) surfaceFields

  inductive SymbolicPlaceHasType :
      SymbolicBodyContext → Surface.Expr → Static.Ty → Prop where
    | local
        (single : SurfaceElaboration.singleNamePath? path = some name)
        (resolved : ResolvesSymbolicLocal context.locals name binding) :
        SymbolicPlaceHasType context (.path path) binding.type
    | selfValue
        (resolved : ResolvesSymbolicLocal context.locals "self" binding) :
        SymbolicPlaceHasType context .selfValue binding.type
    | field
        (base : SymbolicPlaceHasType context surfaceBase receiverType)
        (selected : SelectsSymbolicField context receiverType name fieldType) :
        SymbolicPlaceHasType context (.member surfaceBase name) fieldType
    | indexArray
        (base : SymbolicPlaceHasType context surfaceBase
          (.array elementType length))
        (index : SymbolicExprInfers context surfaceIndex indexType)
        (integer : SymbolicIntegerType indexType) :
        SymbolicPlaceHasType context (.index surfaceBase surfaceIndex) elementType
    | indexSlice
        (base : SymbolicPlaceHasType context surfaceBase (.slice elementType))
        (index : SymbolicExprInfers context surfaceIndex indexType)
        (integer : SymbolicIntegerType indexType) :
        SymbolicPlaceHasType context (.index surfaceBase surfaceIndex) elementType

  inductive SymbolicPatternChecks :
      SymbolicBodyContext → Static.Ty → Surface.Pattern →
        List SymbolicLocalBinding → Prop where
    | wildcard : SymbolicPatternChecks context type .wildcard []
    | bind
        (single : SurfaceElaboration.singleNamePath? path = some name)
        (notVariant : SurfaceElaboration.NoGlobalValueResolution
          context.globals path) :
        SymbolicPatternChecks context type (.path path []) [{ name, type }]
    | integer
        (literal : LiteralChecksSymbolic context.globals.target
          (.integer text) type) :
        SymbolicPatternChecks context type (.integer text) []
    | boolean : SymbolicPatternChecks context (.scalar .bool)
        (.boolean value) []
    | variant
        (receiver : type = .nominal constructor.sourceType
          typeArguments constArguments)
        (selected : SelectsSymbolicVariantConstructor context path constructor)
        (arguments : Static.SymbolicArgumentsBound substitution
          constructor.genericParameters typeArguments constArguments)
        (payloadTypes : Static.substituteTypes substitution constructor.payload =
          some expectedPayload)
        (payload : SymbolicPatternsCheck context expectedPayload
          surfacePayload bindings)
        (distinct : (bindings.map (·.name)).Pairwise (· ≠ ·)) :
        SymbolicPatternChecks context type (.path path surfacePayload) bindings

  inductive SymbolicPatternsCheck :
      SymbolicBodyContext → List Static.Ty → List Surface.Pattern →
        List SymbolicLocalBinding → Prop where
    | nil : SymbolicPatternsCheck context [] [] []
    | cons
        (head : SymbolicPatternChecks context headType surfaceHead headBindings)
        (tail : SymbolicPatternsCheck context tailTypes surfaceTail tailBindings)
        (distinct : ((headBindings ++ tailBindings).map (·.name)).Pairwise (· ≠ ·)) :
        SymbolicPatternsCheck context (headType :: tailTypes)
          (surfaceHead :: surfaceTail) (headBindings ++ tailBindings)

  inductive SymbolicMatchArmsCheck :
      SymbolicBodyContext → Static.Ty → Static.Ty →
        List (Surface.Pattern × Surface.Expr) → Prop where
    | nil : SymbolicMatchArmsCheck context scrutineeType resultType []
    | cons
        (pattern : SymbolicPatternChecks context scrutineeType
          surfacePattern bindings)
        (body : SymbolicExprChecks (context.bindMany bindings)
          surfaceBody resultType)
        (tail : SymbolicMatchArmsCheck context scrutineeType resultType surfaceTail) :
        SymbolicMatchArmsCheck context scrutineeType resultType
          ((surfacePattern, surfaceBody) :: surfaceTail)

  /-- The first arm fixes a match expression's symbolic result type; later
      arms are checked contextually against that fixed type. -/
  inductive SymbolicMatchArmsInfer :
      SymbolicBodyContext → Static.Ty → Static.Ty →
        List (Surface.Pattern × Surface.Expr) → Prop where
    | cons
        (pattern : SymbolicPatternChecks context scrutineeType
          surfacePattern bindings)
        (body : SymbolicExprInfers (context.bindMany bindings)
          surfaceBody resultType)
        (tail : SymbolicMatchArmsCheck context scrutineeType resultType surfaceTail) :
        SymbolicMatchArmsInfer context scrutineeType resultType
          ((surfacePattern, surfaceBody) :: surfaceTail)
end

/-- A constructive specialization witness for one inferred symbolic
    expression. It records both the grounded type and the concrete core term. -/
inductive ExprSpecializes
    (substitution : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (surface : Surface.Expr) (symbolicType : Static.Ty) : Prop where
  | intro
      (groundType : Static.GroundTy)
      (core : Core.Expr)
      (typeGrounds : symbolicType.instantiate substitution = some groundType)
      (lowers : SurfaceElaboration.ExprLowers concrete surface groundType core) :
      ExprSpecializes substitution concrete surface symbolicType

/-- Places use the same specialization boundary while producing a concrete
    assignable core place. -/
inductive PlaceSpecializes
    (substitution : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (surface : Surface.Expr) (symbolicType : Static.Ty) : Prop where
  | intro
      (groundType : Static.GroundTy)
      (core : Core.Place)
      (typeGrounds : symbolicType.instantiate substitution = some groundType)
      (lowers : SurfaceElaboration.PlaceLowers concrete surface groundType core) :
      PlaceSpecializes substitution concrete surface symbolicType

/-- The checking-mode counterpart of `ExprSpecializes`. Keeping inference and
    checking distinct preserves the language's explicit coercion boundary. -/
inductive ExprCheckSpecializes
    (substitution : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (surface : Surface.Expr) (symbolicType : Static.Ty) : Prop where
  | intro
      (groundType : Static.GroundTy)
      (core : Core.Expr)
      (typeGrounds : symbolicType.instantiate substitution = some groundType)
      (checks : SurfaceElaboration.ExprChecks concrete surface groundType core) :
      ExprCheckSpecializes substitution concrete surface symbolicType

inductive ExprsSpecialize
    (substitution : Static.Substitution)
    (concrete : SurfaceElaboration.Context) :
    List Surface.Expr → List Static.Ty → Prop where
  | nil : ExprsSpecialize substitution concrete [] []
  | cons
      (head : ExprSpecializes substitution concrete surfaceHead symbolicHead)
      (tail : ExprsSpecialize substitution concrete surfaceTail symbolicTail) :
      ExprsSpecialize substitution concrete (surfaceHead :: surfaceTail)
        (symbolicHead :: symbolicTail)

inductive ExprsCheckSpecialize
    (substitution : Static.Substitution)
    (concrete : SurfaceElaboration.Context) :
    List Surface.Expr → List Static.Ty → Prop where
  | nil : ExprsCheckSpecialize substitution concrete [] []
  | cons
      (head : ExprCheckSpecializes substitution concrete surfaceHead symbolicHead)
      (tail : ExprsCheckSpecialize substitution concrete surfaceTail symbolicTail) :
      ExprsCheckSpecialize substitution concrete (surfaceHead :: surfaceTail)
        (symbolicHead :: symbolicTail)

/-- A symbolic checking derivation and its concrete specialization for the
    same expression list. This is the recursive argument boundary used when a
    selected signature flows expected types into contextual arguments. -/
inductive SymbolicExprsCheckSpecialize
    (substitution : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext) :
    List Surface.Expr → List Static.Ty → Prop where
  | nil : SymbolicExprsCheckSpecialize substitution concrete symbolic [] []
  | cons
      (symbolicHead : SymbolicExprChecks symbolic surfaceHead typeHead)
      (concreteHead : ExprCheckSpecializes substitution concrete
        surfaceHead typeHead)
      (tail : SymbolicExprsCheckSpecialize substitution concrete symbolic
        surfaceTail typeTail) :
      SymbolicExprsCheckSpecialize substitution concrete symbolic
        (surfaceHead :: surfaceTail) (typeHead :: typeTail)

theorem SymbolicExprsCheckSpecialize.symbolicExpressions
    (specialized : SymbolicExprsCheckSpecialize substitution concrete symbolic
      surfaces types) :
    SymbolicExprsCheck symbolic surfaces types := by
  induction specialized with
  | nil => exact .nil
  | cons symbolicHead concreteHead tail tailIH =>
      exact .cons symbolicHead tailIH

theorem SymbolicExprsCheckSpecialize.concreteExpressions
    (specialized : SymbolicExprsCheckSpecialize substitution concrete symbolic
      surfaces types) :
    ExprsCheckSpecialize substitution concrete surfaces types := by
  induction specialized with
  | nil => exact .nil
  | cons symbolicHead concreteHead tail tailIH =>
      exact .cons concreteHead tailIH

/-- A checked symbolic pattern and its exact concrete lowering share the same
    grounded scrutinee type and corresponding lexical bindings. -/
inductive PatternSpecializes
    (substitution : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (surface : Surface.Pattern) (symbolicType : Static.Ty)
    (symbolicBindings : List SymbolicLocalBinding) : Prop where
  | intro
      (groundType : Static.GroundTy)
      (core : Core.Pattern)
      (concreteBindings : List SurfaceElaboration.LocalBinding)
      (typeGrounds : symbolicType.instantiate substitution = some groundType)
      (lowers : SurfaceElaboration.PatternLowers concrete groundType surface core
        concreteBindings)
      (bindings : SymbolicBindingsSpecialize substitution symbolicBindings
        concreteBindings) :
      PatternSpecializes substitution concrete surface symbolicType symbolicBindings

theorem ExprsSpecialize.lowers
    (specialized : ExprsSpecialize substitution concrete surfaces symbolicTypes) :
    ∃ groundTypes coreExpressions,
      Static.instantiateTypes substitution symbolicTypes = some groundTypes ∧
      SurfaceElaboration.ExprsLower concrete surfaces groundTypes coreExpressions := by
  induction specialized with
  | nil => exact ⟨[], [], rfl, .nil⟩
  | cons head tail tailIH =>
      cases head with
      | intro groundHead coreHead headGrounds headLowers =>
          obtain ⟨groundTail, coreTail, tailGrounds, tailLowers⟩ := tailIH
          exact ⟨groundHead :: groundTail, coreHead :: coreTail, by
            simp [Static.instantiateTypes, headGrounds, tailGrounds],
            .cons headLowers tailLowers⟩

theorem ExprsCheckSpecialize.checks
    (specialized : ExprsCheckSpecialize substitution concrete surfaces symbolicTypes) :
    ∃ groundTypes coreExpressions,
      Static.instantiateTypes substitution symbolicTypes = some groundTypes ∧
      SurfaceElaboration.ExprsCheck concrete surfaces groundTypes coreExpressions := by
  induction specialized with
  | nil => exact ⟨[], [], rfl, .nil⟩
  | cons head tail tailIH =>
      cases head with
      | intro groundHead coreHead headGrounds headChecks =>
          obtain ⟨groundTail, coreTail, tailGrounds, tailChecks⟩ := tailIH
          exact ⟨groundHead :: groundTail, coreHead :: coreTail, by
            simp [Static.instantiateTypes, headGrounds, tailGrounds],
            .cons headChecks tailChecks⟩

theorem ExprsCheckSpecialize.asSymbolic
    (specialized : ExprsCheckSpecialize substitution concrete surfaces symbolicTypes) :
    ∃ cores, SurfaceElaboration.SymbolicExprsCheck concrete substitution
      surfaces symbolicTypes cores := by
  induction specialized with
  | nil => exact ⟨[], .nil⟩
  | cons head tail tailIH =>
      cases head with
      | intro groundHead coreHead headGrounds headChecks =>
          obtain ⟨coreTail, tailChecks⟩ := tailIH
          exact ⟨coreHead :: coreTail, .cons headGrounds headChecks tailChecks⟩

/-- Coupled checking for arguments whose declared types first receive an inner
    symbolic substitution and then the enclosing ground substitution. This is
    the payload/field boundary used by generic constructors. -/
inductive ExprsSubstitutedCheckSpecialize
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (inner : Static.SymbolicSubstitution) :
    List Surface.Expr → List Static.Ty → Prop where
  | nil : ExprsSubstitutedCheckSpecialize outer concrete symbolic inner [] []
  | cons
      (substituted : originalHead.substitute inner = some substitutedHead)
      (symbolicCheck : SymbolicExprChecks symbolic surfaceHead substitutedHead)
      (concreteCheck : ExprCheckSpecializes outer concrete surfaceHead substitutedHead)
      (tail : ExprsSubstitutedCheckSpecialize outer concrete symbolic inner
        surfaceTail originalTail) :
      ExprsSubstitutedCheckSpecialize outer concrete symbolic inner
        (surfaceHead :: surfaceTail) (originalHead :: originalTail)

theorem ExprsSubstitutedCheckSpecialize.symbolic
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {inner : Static.SymbolicSubstitution}
    {surfaces : List Surface.Expr} {originalTypes : List Static.Ty}
    (specialized : ExprsSubstitutedCheckSpecialize outer concrete symbolic inner
      surfaces originalTypes) :
    SymbolicExprsSubstitutedCheck symbolic inner surfaces originalTypes := by
  induction specialized with
  | nil => exact .nil
  | cons substituted symbolicCheck concreteCheck tail tailIH =>
      exact .cons substituted symbolicCheck tailIH

theorem ExprsSubstitutedCheckSpecialize.concrete
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {inner : Static.SymbolicSubstitution}
    {surfaces : List Surface.Expr} {originalTypes : List Static.Ty}
    (specialized : ExprsSubstitutedCheckSpecialize outer concrete symbolic inner
      surfaces originalTypes) :
    ∃ cores, SurfaceElaboration.SymbolicExprsCheck concrete
      (inner.composeGround outer) surfaces originalTypes cores := by
  induction specialized with
  | nil => exact ⟨[], .nil⟩
  | cons substituted symbolicCheck concreteCheck tail tailIH =>
      cases concreteCheck with
      | intro groundHead coreHead headGrounds headChecks =>
          obtain ⟨coreTail, tailChecks⟩ := tailIH
          exact ⟨coreHead :: coreTail,
            .cons (Static.Ty.substitute_then_instantiate substituted headGrounds)
              headChecks tailChecks⟩

/-- Coupled inference for argument lists that determine a generic
    substitution. Each observed symbolic argument and its concrete lowering
    are matched against the same declared parameter type. -/
inductive ExprsInferMatchedSpecialize
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (inner : Static.SymbolicSubstitution) :
    List Surface.Expr → List Static.Ty → List Static.Ty → Prop where
  | nil : ExprsInferMatchedSpecialize outer concrete symbolic inner [] [] []
  | cons
      (symbolicInference : SymbolicExprInfers symbolic surfaceHead observedHead)
      (concreteInference : ExprSpecializes outer concrete surfaceHead observedHead)
      (matched : Static.TySymbolicallyMatches inner patternHead observedHead)
      (tail : ExprsInferMatchedSpecialize outer concrete symbolic inner
        surfaceTail patternTail observedTail) :
      ExprsInferMatchedSpecialize outer concrete symbolic inner
        (surfaceHead :: surfaceTail) (patternHead :: patternTail)
        (observedHead :: observedTail)

theorem ExprsInferMatchedSpecialize.symbolicExpressions
    (specialized : ExprsInferMatchedSpecialize outer concrete symbolic inner
      surfaces patterns observed) :
    SymbolicExprsInfer symbolic surfaces observed := by
  induction specialized with
  | nil => exact .nil
  | cons symbolicInference concreteInference matched tail tailIH =>
      exact .cons symbolicInference tailIH

theorem ExprsInferMatchedSpecialize.symbolicMatches
    (specialized : ExprsInferMatchedSpecialize outer concrete symbolic inner
      surfaces patterns observed) :
    Static.TypesSymbolicallyMatch inner patterns observed := by
  induction specialized with
  | nil => exact .nil
  | cons symbolicInference concreteInference matched tail tailIH =>
      exact .cons matched tailIH

theorem ExprsInferMatchedSpecialize.checkSpecializes
    (specialized : ExprsInferMatchedSpecialize outer concrete symbolic inner
      surfaces patterns observed) :
    ExprsCheckSpecialize outer concrete surfaces observed := by
  induction specialized with
  | nil => exact .nil
  | cons symbolicInference concreteInference matched tail tailIH =>
      cases concreteInference with
      | intro groundHead coreHead headGrounds headLowers =>
          exact .cons (.intro groundHead coreHead headGrounds (.exact headLowers))
            tailIH

theorem ExprsInferMatchedSpecialize.concrete
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {inner : Static.SymbolicSubstitution}
    {surfaces : List Surface.Expr} {patterns observed : List Static.Ty}
    (specialized : ExprsInferMatchedSpecialize outer concrete symbolic inner
      surfaces patterns observed) :
    ∃ cores, SurfaceElaboration.SymbolicExprsInfer concrete
      (inner.composeGround outer) surfaces patterns cores := by
  induction specialized with
  | nil => exact ⟨[], .nil⟩
  | cons symbolicInference concreteInference matched tail tailIH =>
      cases concreteInference with
      | intro groundHead coreHead headGrounds headLowers =>
          obtain ⟨coreTail, tailLowers⟩ := tailIH
          exact ⟨coreHead :: coreTail,
            .cons headLowers
              (matched.composeGround
                (Static.Ty.matchesOfInstantiate headGrounds))
              tailLowers⟩

inductive StructFieldsCheckSpecialize
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (inner : Static.SymbolicSubstitution) :
    List SurfaceElaboration.StructFieldScheme →
      List (Surface.Name × Surface.Expr) → Prop where
  | nil : StructFieldsCheckSpecialize outer concrete symbolic inner [] []
  | cons
      (removed : SurfaceElaboration.RemovesNamedField field.name
        surfaceFields surfaceValue remainder)
      (substituted : field.type.substitute inner = some expectedType)
      (symbolicCheck : SymbolicExprChecks symbolic surfaceValue expectedType)
      (concreteCheck : ExprCheckSpecializes outer concrete surfaceValue expectedType)
      (tail : StructFieldsCheckSpecialize outer concrete symbolic inner
        fieldTail remainder) :
      StructFieldsCheckSpecialize outer concrete symbolic inner
        (field :: fieldTail) surfaceFields

theorem StructFieldsCheckSpecialize.symbolic
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {inner : Static.SymbolicSubstitution}
    {fields : List SurfaceElaboration.StructFieldScheme}
    {surfaceFields : List (Surface.Name × Surface.Expr)}
    (specialized : StructFieldsCheckSpecialize outer concrete symbolic inner
      fields surfaceFields) :
    SymbolicStructFieldsCheck symbolic inner fields surfaceFields := by
  induction specialized with
  | nil => exact .nil
  | cons removed substituted symbolicCheck concreteCheck tail tailIH =>
      exact .cons removed substituted symbolicCheck tailIH

theorem StructFieldsCheckSpecialize.concrete
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {inner : Static.SymbolicSubstitution}
    {fields : List SurfaceElaboration.StructFieldScheme}
    {surfaceFields : List (Surface.Name × Surface.Expr)}
    (specialized : StructFieldsCheckSpecialize outer concrete symbolic inner
      fields surfaceFields) :
    ∃ cores, SurfaceElaboration.StructSchemeFieldsCheck concrete
      (inner.composeGround outer) fields surfaceFields cores := by
  induction specialized with
  | nil => exact ⟨[], .nil⟩
  | cons removed substituted symbolicCheck concreteCheck tail tailIH =>
      cases concreteCheck with
      | intro groundValue coreValue valueGrounds valueChecks =>
          obtain ⟨coreTail, tailChecks⟩ := tailIH
          exact ⟨coreValue :: coreTail,
            .cons removed
              (Static.Ty.substitute_then_instantiate substituted valueGrounds)
              valueChecks tailChecks⟩

inductive StructFieldsInferMatchedSpecialize
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (inner : Static.SymbolicSubstitution) :
    List SurfaceElaboration.StructFieldScheme →
      List (Surface.Name × Surface.Expr) → Prop where
  | nil : StructFieldsInferMatchedSpecialize outer concrete symbolic inner [] []
  | cons
      (removed : SurfaceElaboration.RemovesNamedField field.name
        surfaceFields surfaceValue remainder)
      (symbolicInference : SymbolicExprInfers symbolic surfaceValue actualType)
      (concreteInference : ExprSpecializes outer concrete surfaceValue actualType)
      (matched : Static.TySymbolicallyMatches inner field.type actualType)
      (tail : StructFieldsInferMatchedSpecialize outer concrete symbolic inner
        fieldTail remainder) :
      StructFieldsInferMatchedSpecialize outer concrete symbolic inner
        (field :: fieldTail) surfaceFields

theorem StructFieldsInferMatchedSpecialize.symbolic
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {inner : Static.SymbolicSubstitution}
    {fields : List SurfaceElaboration.StructFieldScheme}
    {surfaceFields : List (Surface.Name × Surface.Expr)}
    (specialized : StructFieldsInferMatchedSpecialize outer concrete symbolic inner
      fields surfaceFields) :
    SymbolicStructFieldsInfer symbolic inner fields surfaceFields := by
  induction specialized with
  | nil => exact .nil
  | cons removed symbolicInference concreteInference matched tail tailIH =>
      exact .cons removed symbolicInference matched tailIH

theorem StructFieldsInferMatchedSpecialize.concrete
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {inner : Static.SymbolicSubstitution}
    {fields : List SurfaceElaboration.StructFieldScheme}
    {surfaceFields : List (Surface.Name × Surface.Expr)}
    (specialized : StructFieldsInferMatchedSpecialize outer concrete symbolic inner
      fields surfaceFields) :
    ∃ cores, SurfaceElaboration.StructSchemeFieldsInfer concrete
      (inner.composeGround outer) fields surfaceFields cores := by
  induction specialized with
  | nil => exact ⟨[], .nil⟩
  | cons removed symbolicInference concreteInference matched tail tailIH =>
      cases concreteInference with
      | intro groundValue coreValue valueGrounds valueLowers =>
          obtain ⟨coreTail, tailLowers⟩ := tailIH
          exact ⟨coreValue :: coreTail,
            .cons removed valueLowers
              (matched.composeGround
                (Static.Ty.matchesOfInstantiate valueGrounds))
              tailLowers⟩

theorem ExprSpecializes.checksExact
    (specialized : ExprSpecializes substitution concrete surface type) :
    ExprCheckSpecializes substitution concrete surface type := by
  cases specialized with
  | intro groundType core typeGrounds lowers =>
      exact .intro groundType core typeGrounds (.exact lowers)

/-- Unary typing is entirely scalar, so grounding cannot change either the
    operator domain or the selected concrete lowering rule. -/
theorem SymbolicUnaryHasType.specializes
    (operand : ExprSpecializes substitution concrete surfaceOperand inputType)
    (operation : SymbolicUnaryHasType op inputType outputType) :
    ExprSpecializes substitution concrete (.unary op surfaceOperand) outputType := by
  cases operation with
  | @scalar inputScalar outputScalar typed =>
      cases operand with
      | intro groundType coreExpression typeGrounds lowers =>
          simp [Static.Ty.instantiate] at typeGrounds
          subst groundType
          exact .intro (.scalar outputScalar) (.unary
            (SurfaceElaboration.lowerUnaryOp op) coreExpression) rfl
            (.unary lowers rfl rfl typed)

/-- Binary specialization preserves the symbolic coercion decision exactly.
    In particular, it cannot choose a different cast after monomorphization. -/
theorem SymbolicBinaryHasType.specializes
    (left : ExprSpecializes substitution concrete surfaceLeft leftType)
    (right : ExprSpecializes substitution concrete surfaceRight rightType)
    (operation : SymbolicBinaryHasType op leftType rightType outputType) :
    ExprSpecializes substitution concrete
      (.binary op surfaceLeft surfaceRight) outputType := by
  cases operation with
  | @exact _ leftScalar rightScalar outputScalar typed =>
      cases left with
      | intro leftGround coreLeft leftGrounds leftLowers =>
          simp [Static.Ty.instantiate] at leftGrounds
          subst leftGround
          cases right with
          | intro rightGround coreRight rightGrounds rightLowers =>
              simp [Static.Ty.instantiate] at rightGrounds
              subst rightGround
              exact .intro (.scalar outputScalar)
                (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft coreRight) rfl
                (.binary leftLowers rightLowers rfl rfl rfl typed)
  | @rightCast rightScalar leftScalar _ outputScalar different notPreferred
      conversion typed =>
      cases left with
      | intro leftGround coreLeft leftGrounds leftLowers =>
          simp [Static.Ty.instantiate] at leftGrounds
          subst leftGround
          cases right with
          | intro rightGround coreRight rightGrounds rightLowers =>
              simp [Static.Ty.instantiate] at rightGrounds
              subst rightGround
              exact .intro (.scalar outputScalar)
                (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft
                  (.cast leftScalar coreRight)) rfl
                (.binaryRightCast leftLowers rightLowers different notPreferred
                  conversion rfl typed)
  | @leftCast leftScalar rightScalar _ outputScalar preferred conversion typed =>
      cases left with
      | intro leftGround coreLeft leftGrounds leftLowers =>
          simp [Static.Ty.instantiate] at leftGrounds
          subst leftGround
          cases right with
          | intro rightGround coreRight rightGrounds rightLowers =>
              simp [Static.Ty.instantiate] at rightGrounds
              subst rightGround
              exact .intro (.scalar outputScalar)
                (.binary (SurfaceElaboration.lowerBinaryOp op)
                  (.cast rightScalar coreLeft) coreRight) rfl
                (.binaryLeftCast leftLowers rightLowers preferred conversion
                  rfl typed)

theorem SymbolicAssignOpHasType.specializes
    (operation : SymbolicAssignOpHasType op symbolicType)
    (typeGrounds : symbolicType.instantiate substitution = some groundType)
    (coreGrounds : groundType.toCore monomorphization = some coreType) :
    Typing.AssignOpHasType (SurfaceElaboration.lowerAssignOp op) coreType := by
  cases operation with
  | set => exact .set
  | @scalar scalarType _ typed =>
      simp [Static.Ty.instantiate] at typeGrounds
      subst groundType
      simp [Static.GroundTy.toCore] at coreGrounds
      subst coreType
      exact typed

theorem SymbolicIntegerType.specializes
    (integer : SymbolicIntegerType symbolicType)
    (typeGrounds : symbolicType.instantiate substitution = some groundType) :
    ∃ coreType,
      groundType.toCore monomorphization = some coreType ∧
      Typing.IntegerTy coreType := by
  cases symbolicType with
  | unit => simp [SymbolicIntegerType] at integer
  | scalar scalarType =>
      simp [Static.Ty.instantiate] at typeGrounds
      subst groundType
      exact ⟨.scalar scalarType, rfl, integer⟩
  | parameter parameter => simp [SymbolicIntegerType] at integer
  | array element length => simp [SymbolicIntegerType] at integer
  | slice element => simp [SymbolicIntegerType] at integer
  | reference referent => simp [SymbolicIntegerType] at integer
  | nominal typeId typeArguments constArguments =>
      simp [SymbolicIntegerType] at integer

theorem SymbolicExprInfers.assignSpecializes
    (place : PlaceSpecializes substitution concrete surfacePlace placeType)
    (value : ExprCheckSpecializes substitution concrete surfaceValue placeType)
    (operation : SymbolicAssignOpHasType op placeType)
    (coreGrounds : groundType.toCore concrete.monomorphization = some coreType)
    (placeGrounds : placeType.instantiate substitution = some groundType) :
    ExprSpecializes substitution concrete
      (.assign op surfacePlace surfaceValue) .unit := by
  cases place with
  | intro placeGround corePlace placeTypeGrounds placeLowers =>
      rw [placeGrounds] at placeTypeGrounds
      have placeEquality := Option.some.inj placeTypeGrounds
      subst placeGround
      cases value with
      | intro valueGround coreValue valueTypeGrounds valueChecks =>
          rw [placeGrounds] at valueTypeGrounds
          have valueEquality := Option.some.inj valueTypeGrounds
          subst valueGround
          exact .intro .unit
            (.assign (SurfaceElaboration.lowerAssignOp op) corePlace coreValue) rfl
            (.assign placeLowers valueChecks coreGrounds
              (operation.specializes placeGrounds coreGrounds))

theorem SymbolicExprInfers.arraySpecializes
    (head : ExprSpecializes substitution concrete surfaceHead elementType)
    (tail : ExprsCheckSpecialize substitution concrete surfaceTail
      (List.replicate surfaceTail.length elementType))
    (elementGrounds : elementType.instantiate substitution = some groundElement)
    (elementCore : groundElement.toCore concrete.monomorphization =
      some coreElement) :
    ExprSpecializes substitution concrete (.array (surfaceHead :: surfaceTail))
      (.array elementType (.literal (surfaceHead :: surfaceTail).length)) := by
  cases head with
  | intro groundHead coreHead headGrounds headLowers =>
      rw [elementGrounds] at headGrounds
      have headEquality := Option.some.inj headGrounds
      subst groundHead
      obtain ⟨groundTail, coreTail, tailGrounds, tailChecks⟩ := tail.checks
      have replicated := Static.instantiateTypes_replicate substitution
        elementType groundElement surfaceTail.length elementGrounds
      rw [replicated] at tailGrounds
      have tailEquality := Option.some.inj tailGrounds
      subst groundTail
      exact .intro
        (.array groundElement (surfaceHead :: surfaceTail).length)
        (.array coreElement (coreHead :: coreTail))
        (by simp [Static.Ty.instantiate, Static.Const.instantiate, elementGrounds])
        (.array headLowers tailChecks elementCore)

theorem SymbolicExprChecks.arraySpecializes
    (elements : ExprsCheckSpecialize substitution concrete surfaceElements
      (List.replicate surfaceElements.length elementType))
    (elementGrounds : elementType.instantiate substitution = some groundElement)
    (elementCore : groundElement.toCore concrete.monomorphization =
      some coreElement) :
    ExprCheckSpecializes substitution concrete (.array surfaceElements)
      (.array elementType (.literal surfaceElements.length)) := by
  obtain ⟨groundElements, coreElements, elementsGround, elementsCheck⟩ :=
    elements.checks
  have replicated := Static.instantiateTypes_replicate substitution
    elementType groundElement surfaceElements.length elementGrounds
  rw [replicated] at elementsGround
  have elementsEquality := Option.some.inj elementsGround
  subst groundElements
  exact .intro (.array groundElement surfaceElements.length)
    (.array coreElement coreElements)
    (by simp [Static.Ty.instantiate, Static.Const.instantiate, elementGrounds])
    (.array elementsCheck elementCore)

theorem LiteralInfersSymbolic.specializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (inferred : LiteralInfersSymbolic symbolic.globals.target literal type) :
    ExprSpecializes substitution concrete (.literal literal) type := by
  cases inferred with
  | @default coreExpression lowered =>
      have targetEquality : concrete.target = symbolic.globals.target := by
        rw [specialized.globals]
      have concreteLowered : Elaboration.LiteralElaborates concrete.target literal
          (Elaboration.literalDefaultType literal) coreExpression := by
        rw [targetEquality]
        exact lowered
      exact .intro (.scalar (literalDefaultScalar literal)) coreExpression rfl
        (.literal concreteLowered (by
          simp [Static.GroundTy.toCore, literalDefaultType_eq_scalar]))

theorem LiteralChecksSymbolic.specializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (checked : LiteralChecksSymbolic symbolic.globals.target literal type) :
    ExprCheckSpecializes substitution concrete (.literal literal) type := by
  obtain ⟨scalar, coreExpression, rfl, lowered⟩ := checked
  have targetEquality : concrete.target = symbolic.globals.target := by
    rw [specialized.globals]
  have concreteLowered : Elaboration.LiteralElaborates concrete.target literal
      (.scalar scalar) coreExpression := by
    rw [targetEquality]
    exact lowered
  exact .intro (.scalar scalar) coreExpression rfl
    (.literal (.scalar scalar) concreteLowered rfl)

theorem SymbolicPatternChecks.wildcardSpecializes
    (typeGrounds : symbolicType.instantiate substitution = some groundType) :
    PatternSpecializes substitution concrete .wildcard symbolicType [] := by
  exact .intro groundType .wildcard [] typeGrounds .wildcard .nil

theorem SymbolicPatternChecks.bindSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType groundType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (single : SurfaceElaboration.singleNamePath? path = some name)
    (notVariant : SurfaceElaboration.NoGlobalValueResolution
      symbolic.globals path)
    (typeGrounds : symbolicType.instantiate substitution = some groundType)
    (id : VarId) (fresh : SurfaceElaboration.FreshLocalId concrete id) :
    PatternSpecializes substitution concrete (.path path []) symbolicType
      [{ name, type := symbolicType }] := by
  exact .intro groundType (.bind id) [{ name, id, type := groundType }]
    typeGrounds
    (.bind single (contexts.noGlobalValueResolution notVariant) id fresh)
    (.cons name id typeGrounds .nil)

theorem SymbolicPatternChecks.integerSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (checked : LiteralChecksSymbolic symbolic.globals.target
      (.integer text) symbolicType) :
    PatternSpecializes substitution concrete (.integer text) symbolicType [] := by
  obtain ⟨scalar, coreExpression, rfl, lowered⟩ := checked
  have concreteLowered : Elaboration.LiteralElaborates concrete.target
      (.integer text) (.scalar scalar) coreExpression := by
    rw [show concrete.target = symbolic.globals.target by rw [contexts.globals]]
    exact lowered
  cases concreteLowered with
  | signedInteger parsed upper =>
      exact .intro (.scalar (.signed _)) (.literal (.signed _ _)) [] rfl
        (.integer rfl (.signedInteger parsed upper)) .nil
  | unsignedInteger parsed upper =>
      exact .intro (.scalar (.unsigned _)) (.literal (.unsigned _ _)) [] rfl
        (.integer rfl (.unsignedInteger parsed upper)) .nil
  | nullPointer parsed =>
      exact .intro (.scalar .rawPtr) (.literal (.pointer 0)) [] rfl
        (.integer rfl (.nullPointer parsed)) .nil

theorem SymbolicPatternChecks.booleanSpecializes
    (value : Bool) :
    PatternSpecializes substitution concrete (.boolean value)
      (.scalar .bool) [] := by
  exact .intro (.scalar .bool) (.literal (.boolean value)) [] rfl .boolean .nil

/-- An occurrence-indexed pattern specialization with deterministic local-ID
    allocation. The witness mentions only bindings demanded by this source
    pattern, so a finite function body never needs evidence for hypothetical
    generic instantiations that do not occur. -/
inductive PatternAllocated
    (substitution : Static.Substitution)
    (concrete : SurfaceElaboration.Context) (next : VarId)
    (surface : Surface.Pattern) (symbolicType : Static.Ty)
    (symbolicBindings : List SymbolicLocalBinding) (final : VarId) : Prop where
  | intro
      (groundType : Static.GroundTy)
      (core : Core.Pattern)
      (concreteBindings : List SurfaceElaboration.LocalBinding)
      (typeGrounds : symbolicType.instantiate substitution = some groundType)
      (lowers : SurfaceElaboration.PatternLowers concrete groundType surface core
        concreteBindings)
      (allocation : SymbolicBindingsAllocate substitution next symbolicBindings
        concreteBindings final) :
      PatternAllocated substitution concrete next surface symbolicType
        symbolicBindings final

theorem PatternAllocated.specializes
    (allocated : PatternAllocated substitution concrete next surface
      symbolicType symbolicBindings final) :
    PatternSpecializes substitution concrete surface symbolicType symbolicBindings := by
  cases allocated with
  | intro groundType core concreteBindings typeGrounds lowers allocation =>
      exact .intro groundType core concreteBindings typeGrounds lowers
        allocation.specializes

inductive PatternsAllocated
    (substitution : Static.Substitution)
    (concrete : SurfaceElaboration.Context) :
    VarId → List Surface.Pattern → List Static.Ty →
      List SymbolicLocalBinding → VarId → Prop where
  | nil (next : VarId) : PatternsAllocated substitution concrete next [] [] [] next
  | cons
      (head : PatternAllocated substitution concrete next surfaceHead
        symbolicHead headBindings middle)
      (tail : PatternsAllocated substitution concrete middle surfaceTail
        symbolicTail tailBindings final) :
      PatternsAllocated substitution concrete next
        (surfaceHead :: surfaceTail) (symbolicHead :: symbolicTail)
        (headBindings ++ tailBindings) final

theorem PatternsAllocated.result
    (allocated : PatternsAllocated substitution concrete next surfaces
      symbolicTypes symbolicBindings final) :
    ∃ groundTypes corePatterns concreteBindings,
      Static.instantiateTypes substitution symbolicTypes = some groundTypes ∧
      SurfaceElaboration.PatternsLower concrete groundTypes surfaces corePatterns
        concreteBindings ∧
      SymbolicBindingsAllocate substitution next symbolicBindings
        concreteBindings final := by
  induction allocated with
  | nil => exact ⟨[], [], [], rfl, .nil, .nil _⟩
  | cons head tail tailIH =>
      cases head with
      | intro groundHead coreHead concreteHead headGrounds headLowers
          headAllocation =>
          obtain ⟨groundTail, coreTail, concreteTail, tailGrounds,
            tailLowers, tailAllocation⟩ := tailIH
          exact ⟨groundHead :: groundTail, coreHead :: coreTail,
            concreteHead ++ concreteTail, by
              simp [Static.instantiateTypes, headGrounds, tailGrounds],
            .cons headLowers tailLowers,
            headAllocation.append tailAllocation⟩

theorem PatternAllocated.wildcard
    {groundType : Static.GroundTy}
    (typeGrounds : symbolicType.instantiate substitution = some groundType) :
    PatternAllocated substitution concrete next .wildcard symbolicType [] next :=
  ⟨groundType, .wildcard, [], typeGrounds, .wildcard, .nil next⟩

theorem PatternAllocated.bind
    {symbolic : SymbolicBodyContext}
    {groundReturnType groundType : Static.GroundTy}
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (single : SurfaceElaboration.singleNamePath? path = some name)
    (notVariant : SurfaceElaboration.NoGlobalValueResolution
      symbolic.globals path)
    (typeGrounds : symbolicType.instantiate substitution = some groundType)
    (bounded : SurfaceElaboration.LocalIdsBelow concrete next) :
    PatternAllocated substitution concrete next (.path path []) symbolicType
      [{ name, type := symbolicType }] (next + 1) :=
  ⟨groundType, .bind next, [{ name, id := next, type := groundType }],
    typeGrounds,
    .bind single (contexts.noGlobalValueResolution notVariant) next bounded.fresh,
    .cons typeGrounds (.nil (next + 1))⟩

theorem PatternAllocated.integer
    {symbolic : SymbolicBodyContext}
    {groundReturnType : Static.GroundTy}
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (checked : LiteralChecksSymbolic symbolic.globals.target
      (.integer text) symbolicType) :
    PatternAllocated substitution concrete next (.integer text)
      symbolicType [] next := by
  cases SymbolicPatternChecks.integerSpecializes contexts checked with
  | intro groundType core concreteBindings typeGrounds lowers bindings =>
      cases bindings
      exact ⟨groundType, core, [], typeGrounds, lowers, .nil next⟩

theorem PatternAllocated.boolean (value : Bool) :
    PatternAllocated substitution concrete next (.boolean value)
      (.scalar .bool) [] next :=
  ⟨.scalar .bool, .literal (.boolean value), [], rfl, .boolean, .nil next⟩

/-- Variant-pattern specialization consumes the concrete constructor selected
    for this exact occurrence and recursively allocated payload witnesses. -/
theorem PatternAllocated.variant
    {groundType : Static.GroundTy}
    (typeGrounds : symbolicType.instantiate substitution = some groundType)
    (selected : SurfaceElaboration.SelectsVariant concrete groundType path entry)
    (payload : PatternsAllocated substitution concrete next surfacePayload
      expectedPayload symbolicBindings final)
    (payloadTypes : Static.instantiateTypes substitution expectedPayload =
      some entry.payload)
    (namesDistinct : (symbolicBindings.map (·.name)).Pairwise (· ≠ ·))
    (bounded : SurfaceElaboration.LocalIdsBelow concrete next) :
    PatternAllocated substitution concrete next (.path path surfacePayload)
      symbolicType symbolicBindings final := by
  obtain ⟨groundPayload, corePayload, concreteBindings, payloadGrounds,
    payloadLowers, allocation⟩ := payload.result
  rw [payloadTypes] at payloadGrounds
  have payloadEquality := Option.some.inj payloadGrounds
  subst groundPayload
  exact ⟨groundType, .enumVariant entry.coreType entry.variant corePayload,
    concreteBindings, typeGrounds,
    .variant selected payloadLowers
      (allocation.patternBindingsFresh bounded namesDistinct),
    allocation⟩

/-- The complete specialization rule for a symbolic enum pattern. The source
    constructor fixes the declaration and variant, generic composition fixes
    the receiver and payload types, and the finite artifact demand supplies
    the concrete layout row used by the recursively allocated pattern. -/
theorem SymbolicPatternChecks.variantSpecializes
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (receiver : symbolicType = .nominal constructor.sourceType
      symbolicTypeArguments symbolicConstArguments)
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
    (arguments : Static.SymbolicArgumentsBound inner
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer
      symbolicConstArguments = some groundConstArguments)
    (payloadSubstitute : Static.substituteTypes inner constructor.payload =
      some expectedPayload)
    (payloadGround : Static.instantiateTypes outer expectedPayload =
      some groundPayload)
    (payloadSymbolic : SymbolicPatternsCheck symbolic expectedPayload
      surfacePayload symbolicBindings)
    (payload : PatternsAllocated outer concrete next surfacePayload
      expectedPayload symbolicBindings final)
    (artifact : VariantArtifactDemand concrete constructor
      (.nominal constructor.sourceType groundTypeArguments groundConstArguments)
      groundPayload entry)
    (namesDistinct : (symbolicBindings.map (·.name)).Pairwise (· ≠ ·))
    (bounded : SurfaceElaboration.LocalIdsBelow concrete next) :
    SymbolicPatternChecks symbolic symbolicType (.path path surfacePayload)
        symbolicBindings ∧
      PatternAllocated outer concrete next (.path path surfacePayload)
        symbolicType symbolicBindings final := by
  constructor
  · exact .variant receiver selected arguments payloadSubstitute payloadSymbolic
      namesDistinct
  have selectedGround := artifact.selectsVariant contexts selected
  have receiverGrounds : symbolicType.instantiate outer =
      some (.nominal constructor.sourceType groundTypeArguments
        groundConstArguments) := by
    rw [receiver]
    simp [Static.Ty.instantiate, typeArgumentsGround, constArgumentsGround]
  have payloadTypes : Static.instantiateTypes outer expectedPayload =
      some entry.payload := by
    rw [artifact.payload]
    exact payloadGround
  exact PatternAllocated.variant receiverGrounds selectedGround payload
    payloadTypes namesDistinct bounded

/-- Match arms couple each symbolic pattern/body occurrence to the exact
    concrete bindings and expression used by lowering. Separate arms may reuse
    the same fresh-ID suffix because their lexical scopes are disjoint. -/
inductive MatchArmsCheckSpecialize
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy)
    (symbolic : SymbolicBodyContext)
    (concrete : SurfaceElaboration.Context)
    (next : VarId)
    (symbolicScrutinee symbolicResult : Static.Ty)
    (groundScrutinee groundResult : Static.GroundTy) :
    List (Surface.Pattern × Surface.Expr) →
      List (Core.Pattern × Core.Expr) → Prop where
  | nil
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next) :
      MatchArmsCheckSpecialize substitution groundReturnType symbolic concrete next
        symbolicScrutinee symbolicResult groundScrutinee groundResult [] []
  | cons
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (scrutineeGrounds : symbolicScrutinee.instantiate substitution =
        some groundScrutinee)
      (resultGrounds : symbolicResult.instantiate substitution = some groundResult)
      (patternTyped : SymbolicPatternChecks symbolic symbolicScrutinee
        surfacePattern symbolicBindings)
      (patternLowers : SurfaceElaboration.PatternLowers concrete groundScrutinee
        surfacePattern corePattern concreteBindings)
      (allocation : SymbolicBindingsAllocate substitution next symbolicBindings
        concreteBindings patternFinal)
      (bodyTyped : SymbolicExprChecks (symbolic.bindMany symbolicBindings)
        surfaceBody symbolicResult)
      (bodyLowers : SurfaceElaboration.ExprChecks
        (concrete.bindLocals concreteBindings) surfaceBody groundResult coreBody)
      (tail : MatchArmsCheckSpecialize substitution groundReturnType symbolic concrete
        next symbolicScrutinee symbolicResult groundScrutinee groundResult
        surfaceTail coreTail) :
      MatchArmsCheckSpecialize substitution groundReturnType symbolic concrete next
        symbolicScrutinee symbolicResult groundScrutinee groundResult
        ((surfacePattern, surfaceBody) :: surfaceTail)
        ((corePattern, coreBody) :: coreTail)

theorem MatchArmsCheckSpecialize.symbolic
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context} {next : VarId}
    {symbolicScrutinee symbolicResult : Static.Ty}
    {groundScrutinee groundResult : Static.GroundTy}
    {surface : List (Surface.Pattern × Surface.Expr)}
    {core : List (Core.Pattern × Core.Expr)}
    (specialized : MatchArmsCheckSpecialize substitution groundReturnType symbolic
      concrete next symbolicScrutinee symbolicResult groundScrutinee groundResult
      surface core) :
    SymbolicMatchArmsCheck symbolic symbolicScrutinee symbolicResult surface := by
  induction specialized with
  | nil => exact .nil
  | cons contexts bounded scrutineeGrounds resultGrounds patternTyped patternLowers
      allocation bodyTyped bodyLowers tail tailIH =>
      exact .cons patternTyped bodyTyped tailIH

theorem MatchArmsCheckSpecialize.lowers
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context} {next : VarId}
    {symbolicScrutinee symbolicResult : Static.Ty}
    {groundScrutinee groundResult : Static.GroundTy}
    {surface : List (Surface.Pattern × Surface.Expr)}
    {core : List (Core.Pattern × Core.Expr)}
    (specialized : MatchArmsCheckSpecialize substitution groundReturnType symbolic
      concrete next symbolicScrutinee symbolicResult groundScrutinee groundResult
      surface core) :
    SurfaceElaboration.MatchArmsLower concrete groundScrutinee groundResult
      surface core := by
  induction specialized with
  | nil => exact .nil
  | cons contexts bounded scrutineeGrounds resultGrounds patternTyped patternLowers
      allocation bodyTyped bodyLowers tail tailIH =>
      exact .cons patternLowers bodyLowers tailIH

/-- A nonempty match specialization infers the first body and checks the tail
    against that exact result. -/
inductive MatchArmsSpecialize
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy)
    (symbolic : SymbolicBodyContext)
    (concrete : SurfaceElaboration.Context)
    (next : VarId)
    (symbolicScrutinee symbolicResult : Static.Ty)
    (groundScrutinee groundResult : Static.GroundTy) :
    List (Surface.Pattern × Surface.Expr) →
      List (Core.Pattern × Core.Expr) → Prop where
  | cons
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (scrutineeGrounds : symbolicScrutinee.instantiate substitution =
        some groundScrutinee)
      (resultGrounds : symbolicResult.instantiate substitution = some groundResult)
      (patternTyped : SymbolicPatternChecks symbolic symbolicScrutinee
        surfacePattern symbolicBindings)
      (patternLowers : SurfaceElaboration.PatternLowers concrete groundScrutinee
        surfacePattern corePattern concreteBindings)
      (allocation : SymbolicBindingsAllocate substitution next symbolicBindings
        concreteBindings patternFinal)
      (bodyTyped : SymbolicExprInfers (symbolic.bindMany symbolicBindings)
        surfaceBody symbolicResult)
      (bodyLowers : SurfaceElaboration.ExprLowers
        (concrete.bindLocals concreteBindings) surfaceBody groundResult coreBody)
      (tail : MatchArmsCheckSpecialize substitution groundReturnType symbolic
        concrete next symbolicScrutinee symbolicResult groundScrutinee groundResult
        surfaceTail coreTail) :
      MatchArmsSpecialize substitution groundReturnType symbolic concrete next
        symbolicScrutinee symbolicResult groundScrutinee groundResult
        ((surfacePattern, surfaceBody) :: surfaceTail)
        ((corePattern, coreBody) :: coreTail)

theorem MatchArmsSpecialize.symbolic
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context} {next : VarId}
    {symbolicScrutinee symbolicResult : Static.Ty}
    {groundScrutinee groundResult : Static.GroundTy}
    {surface : List (Surface.Pattern × Surface.Expr)}
    {core : List (Core.Pattern × Core.Expr)}
    (specialized : MatchArmsSpecialize substitution groundReturnType symbolic
      concrete next symbolicScrutinee symbolicResult groundScrutinee groundResult
      surface core) :
    SymbolicMatchArmsInfer symbolic symbolicScrutinee symbolicResult surface := by
  cases specialized with
  | cons _contexts _bounded _scrutineeGrounds _resultGrounds patternTyped
      _patternLowers _allocation bodyTyped _bodyLowers tail =>
      exact .cons patternTyped bodyTyped tail.symbolic

theorem MatchArmsSpecialize.lowers
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context} {next : VarId}
    {symbolicScrutinee symbolicResult : Static.Ty}
    {groundScrutinee groundResult : Static.GroundTy}
    {surface : List (Surface.Pattern × Surface.Expr)}
    {core : List (Core.Pattern × Core.Expr)}
    (specialized : MatchArmsSpecialize substitution groundReturnType symbolic
      concrete next symbolicScrutinee symbolicResult groundScrutinee groundResult
      surface core) :
    SurfaceElaboration.MatchArmsInfer concrete groundScrutinee groundResult
      surface core := by
  cases specialized with
  | cons _contexts _bounded _scrutineeGrounds _resultGrounds _patternTyped
      patternLowers _allocation _bodyTyped bodyLowers tail =>
      exact .cons patternLowers bodyLowers tail.lowers

theorem SymbolicExprInfers.matchValueSpecializes
    {substitution : Static.Substitution}
    {groundReturnType groundScrutinee groundResult : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context} {next : VarId}
    {symbolicScrutinee symbolicResult : Static.Ty}
    {surfaceScrutinee : Surface.Expr}
    {surfaceArms : List (Surface.Pattern × Surface.Expr)}
    {coreArms : List (Core.Pattern × Core.Expr)}
    (scrutinee : ExprSpecializes substitution concrete surfaceScrutinee
      symbolicScrutinee)
    (scrutineeGrounds : symbolicScrutinee.instantiate substitution =
      some groundScrutinee)
    (resultGrounds : symbolicResult.instantiate substitution = some groundResult)
    (arms : MatchArmsSpecialize substitution groundReturnType symbolic concrete next
      symbolicScrutinee symbolicResult groundScrutinee groundResult
      surfaceArms coreArms) :
    ExprSpecializes substitution concrete
      (.matchValue surfaceScrutinee surfaceArms) symbolicResult := by
  cases scrutinee with
  | intro actualScrutinee coreScrutinee actualGrounds scrutineeLowers =>
      rw [scrutineeGrounds] at actualGrounds
      have scrutineeEquality := Option.some.inj actualGrounds
      subst actualScrutinee
      exact .intro groundResult (.matchValue coreScrutinee coreArms) resultGrounds
        (.matchValue scrutineeLowers arms.lowers)

theorem ExprCheckSpecializes.scalarCast
    (inferred : ExprSpecializes substitution concrete surface
      (.scalar sourceType))
    (notContextualLiteral : ¬ SurfaceElaboration.ContextualScalarLiteralApplies
      concrete.target surface targetType)
    (different : sourceType ≠ targetType)
    (conversion : Typing.ScalarCast sourceType targetType) :
    ExprCheckSpecializes substitution concrete surface (.scalar targetType) := by
  cases inferred with
  | intro groundType coreExpression typeGrounds lowers =>
      simp [Static.Ty.instantiate] at typeGrounds
      subst groundType
      exact .intro (.scalar targetType) (.cast targetType coreExpression) rfl
        (.scalarCast lowers notContextualLiteral different conversion)

theorem ExprCheckSpecializes.arrayToSlice
    (array : ExprSpecializes substitution concrete surface
      (.array elementType length))
    (elementGrounds : elementType.instantiate substitution = some groundElement)
    (elementCore : groundElement.toCore concrete.monomorphization =
      some coreElement) :
    ExprCheckSpecializes substitution concrete surface (.slice elementType) := by
  cases array with
  | intro groundType coreArray typeGrounds lowers =>
      cases lengthGrounds : length.instantiate substitution with
      | none =>
          simp [Static.Ty.instantiate, elementGrounds, lengthGrounds] at typeGrounds
      | some groundLength =>
          simp [Static.Ty.instantiate, elementGrounds, lengthGrounds] at typeGrounds
          subst groundType
          exact .intro (.slice groundElement) (.arrayToSlice coreElement coreArray)
            (by simp [Static.Ty.instantiate, elementGrounds])
            (.arrayToSlice lowers elementCore)

theorem SymbolicExprInfers.signedMinimumLiteralSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (lowered : ∃ expression,
      Elaboration.SignedMinimumLiteralElaborates
        symbolic.globals.target text .i32 expression) :
    ExprSpecializes substitution concrete
      (.unary .negative (.literal (.integer text)))
      (.scalar (.signed .i32)) := by
  obtain ⟨coreExpression, lowered⟩ := lowered
  have targetEquality : concrete.target = symbolic.globals.target := by
    rw [specialized.globals]
  have concreteLowered : Elaboration.SignedMinimumLiteralElaborates
      concrete.target text .i32 coreExpression := by
    rw [targetEquality]
    exact lowered
  exact .intro (.scalar (.signed .i32)) coreExpression rfl
    (.signedMinimumLiteral concreteLowered (by
      simp [Static.GroundTy.toCore]))

theorem SymbolicExprChecks.signedMinimumLiteralSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (signed : type = .scalar (.signed signedType))
    (checked : ∃ expression,
      Elaboration.SignedMinimumLiteralElaborates
        symbolic.globals.target text signedType expression) :
    ExprCheckSpecializes substitution concrete
      (.unary .negative (.literal (.integer text))) type := by
  subst type
  obtain ⟨coreExpression, lowered⟩ := checked
  have targetEquality : concrete.target = symbolic.globals.target := by
    rw [specialized.globals]
  have concreteLowered : Elaboration.SignedMinimumLiteralElaborates
      concrete.target text signedType coreExpression := by
    rw [targetEquality]
    exact lowered
  exact .intro (.scalar (.signed signedType)) coreExpression rfl
    (.signedMinimumLiteral concreteLowered rfl)

theorem SymbolicExprChecks.unaryLiteralSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (scalar : type = .scalar scalarType)
    (literal : ∃ expression,
      Elaboration.LiteralElaborates symbolic.globals.target surfaceLiteral
        (.scalar scalarType) expression)
    (typed : Typing.UnaryOpHasType (SurfaceElaboration.lowerUnaryOp op)
      (.scalar scalarType) (.scalar scalarType)) :
    ExprCheckSpecializes substitution concrete
      (.unary op (.literal surfaceLiteral)) type := by
  subst type
  obtain ⟨coreOperand, lowered⟩ := literal
  have targetEquality : concrete.target = symbolic.globals.target := by
    rw [specialized.globals]
  have concreteLowered : Elaboration.LiteralElaborates concrete.target
      surfaceLiteral (.scalar scalarType) coreOperand := by
    rw [targetEquality]
    exact lowered
  exact .intro (.scalar scalarType)
    (.unary (SurfaceElaboration.lowerUnaryOp op) coreOperand) rfl
    (.unaryLiteral concreteLowered rfl typed)

theorem SymbolicExprInfers.binaryNullPointerRightSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (left : ExprSpecializes substitution concrete surfaceLeft (.scalar .rawPtr))
    (null : LiteralChecksSymbolic symbolic.globals.target
      (.integer text) (.scalar .rawPtr))
    (operation : SymbolicBinaryHasType op (.scalar .rawPtr)
      (.scalar .rawPtr) outputType) :
    ExprSpecializes substitution concrete
      (.binary op surfaceLeft (.literal (.integer text))) outputType := by
  obtain ⟨scalar, coreRight, scalarEquality, nullLowers⟩ := null
  simp at scalarEquality
  subst scalar
  have concreteNull : Elaboration.LiteralElaborates concrete.target
      (.integer text) (.scalar .rawPtr) coreRight := by
    rw [show concrete.target = symbolic.globals.target by rw [contexts.globals]]
    exact nullLowers
  cases operation with
  | @exact _ _ _ outputScalar typed =>
      cases left with
      | intro leftGround coreLeft leftGrounds leftLowers =>
          simp [Static.Ty.instantiate] at leftGrounds
          subst leftGround
          exact .intro (.scalar outputScalar)
            (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft coreRight) rfl
            (.binaryNullPointerRight leftLowers concreteNull rfl typed)
  | rightCast different notPreferred conversion typed => exact (different rfl).elim
  | leftCast preferred conversion typed => cases preferred

theorem SymbolicExprInfers.binaryNullPointerLeftSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (null : LiteralChecksSymbolic symbolic.globals.target
      (.integer text) (.scalar .rawPtr))
    (right : ExprSpecializes substitution concrete surfaceRight (.scalar .rawPtr))
    (operation : SymbolicBinaryHasType op (.scalar .rawPtr)
      (.scalar .rawPtr) outputType) :
    ExprSpecializes substitution concrete
      (.binary op (.literal (.integer text)) surfaceRight) outputType := by
  obtain ⟨scalar, coreLeft, scalarEquality, nullLowers⟩ := null
  simp at scalarEquality
  subst scalar
  have concreteNull : Elaboration.LiteralElaborates concrete.target
      (.integer text) (.scalar .rawPtr) coreLeft := by
    rw [show concrete.target = symbolic.globals.target by rw [contexts.globals]]
    exact nullLowers
  cases operation with
  | @exact _ _ _ outputScalar typed =>
      cases right with
      | intro rightGround coreRight rightGrounds rightLowers =>
          simp [Static.Ty.instantiate] at rightGrounds
          subst rightGround
          exact .intro (.scalar outputScalar)
            (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft coreRight) rfl
            (.binaryNullPointerLeft concreteNull rightLowers rfl typed)
  | rightCast different notPreferred conversion typed => exact (different rfl).elim
  | leftCast preferred conversion typed => cases preferred

theorem SymbolicExprInfers.localSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (single : SurfaceElaboration.singleNamePath? path = some name)
    (resolved : ResolvesSymbolicLocal symbolic.locals name binding) :
    ExprSpecializes substitution concrete (.path path) binding.type := by
  obtain ⟨concreteBinding, concreteResolved, typeGrounds⟩ :=
    specialized.locals.forward name binding resolved
  exact .intro concreteBinding.type (.local concreteBinding.id) typeGrounds
    (.local (binding := concreteBinding) name single concreteResolved)

theorem SymbolicExprInfers.selfSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (resolved : ResolvesSymbolicLocal symbolic.locals "self" binding) :
    ExprSpecializes substitution concrete .selfValue binding.type := by
  obtain ⟨concreteBinding, concreteResolved, typeGrounds⟩ :=
    specialized.locals.forward "self" binding resolved
  exact .intro concreteBinding.type (.local concreteBinding.id) typeGrounds
    (.selfValue concreteResolved)

theorem SymbolicExprInfers.constantSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (selected : SourceWellFormed.SelectsConstant
      symbolic.scopeContext path entry) :
    ExprSpecializes substitution concrete (.path path) entry.type.toTy := by
  rcases selected with
    ⟨notShadowed, symbol, resolved, member, declaration, unique⟩
  have concreteNotShadowed := specialized.globalPathNotShadowed notShadowed
  have concreteResolved : SurfaceElaboration.ResolvesGlobal
      concrete .value path symbol := by
    cases resolved with
    | intro reference formed namesResolved =>
        apply SurfaceElaboration.ResolvesGlobal.intro reference formed
        rw [specialized.globals]
        exact namesResolved
  have concreteMember : entry ∈ concrete.constants := by
    rw [specialized.globals]
    exact member
  exact .intro entry.type (.constant entry.constant)
    (Static.GroundTy.toTy_instantiate entry.type substitution)
    (.constant (.intro concreteNotShadowed symbol concreteResolved
      concreteMember declaration))

theorem SymbolicExprInfers.printI32Specializes
    {substitution : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    (builtin : SurfaceElaboration.builtinIntrinsic? path = some .printI32)
    (argument : ExprCheckSpecializes substitution concrete surfaceArgument
      (.scalar (.signed .i32))) :
    ExprSpecializes substitution concrete
      (.call (.path path) [surfaceArgument]) .unit := by
  cases argument with
  | intro argumentGround coreArgument argumentGrounds argumentChecks =>
      simp [Static.Ty.instantiate] at argumentGrounds
      subst argumentGround
      exact .intro .unit (.intrinsic .printI32 coreArgument) rfl
        (.printI32 rfl builtin argumentChecks)

theorem SymbolicExprInfers.assertSpecializes
    {substitution : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    (builtin : SurfaceElaboration.builtinIntrinsic? path = some .assert)
    (argument : ExprCheckSpecializes substitution concrete surfaceArgument
      (.scalar .bool)) :
    ExprSpecializes substitution concrete
      (.call (.path path) [surfaceArgument]) .unit := by
  cases argument with
  | intro argumentGround coreArgument argumentGrounds argumentChecks =>
      simp [Static.Ty.instantiate] at argumentGrounds
      subst argumentGround
      exact .intro .unit (.intrinsic .assert coreArgument) rfl
        (.assert rfl builtin argumentChecks)

theorem SymbolicExprInfers.i32ArrayDataPtrSpecializes
    {substitution : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    (builtin : SurfaceElaboration.builtinIntrinsic? path =
      some .i32ArrayDataPtr)
    (argument : ExprCheckSpecializes substitution concrete surfaceArgument
      (.array (.scalar (.signed .i32)) length)) :
    ExprSpecializes substitution concrete
      (.call (.path path) [surfaceArgument]) (.scalar .rawPtr) := by
  cases argument with
  | intro argumentGround coreArgument argumentGrounds argumentChecks =>
      cases lengthGrounds : length.instantiate substitution with
      | none =>
          simp [Static.Ty.instantiate, lengthGrounds] at argumentGrounds
      | some groundLength =>
          simp only [Static.Ty.instantiate] at argumentGrounds
          rw [lengthGrounds] at argumentGrounds
          simp at argumentGrounds
          subst argumentGround
          exact .intro (.scalar .rawPtr) (.i32ArrayDataPtr coreArgument) rfl
            (.i32ArrayDataPtr rfl builtin argumentChecks)

/-- Direct-call specialization consumes the one resolved monomorphic instance
    demanded by this call occurrence. The argument and result equalities ensure
    that the catalog row is the grounding of the symbolic signature, rather
    than merely another callable function with the same surface path. -/
theorem SymbolicExprInfers.directCallSpecializes
    (arguments : ExprsCheckSpecialize substitution concrete surfaceArguments
      symbolicParameterTypes)
    (parameterGrounds : Static.instantiateTypes substitution
      symbolicParameterTypes = some resolved.parameterTypes)
    (resolvedCall : SurfaceElaboration.ResolvesDirectCall concrete path
      resolved.parameterTypes scheme resolved)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
    (returnGrounds : symbolicReturnType.instantiate substitution =
      some resolved.returnType) :
    ExprSpecializes substitution concrete
      (.call (.path path) surfaceArguments) symbolicReturnType := by
  obtain ⟨groundArguments, coreArguments, argumentsGround,
    argumentsCheck⟩ := arguments.checks
  rw [parameterGrounds] at argumentsGround
  have argumentEquality := Option.some.inj argumentsGround
  subst groundArguments
  exact .intro resolved.returnType (.call resolved.function coreArguments)
    returnGrounds (.directCall argumentsCheck resolvedCall notIntrinsic rfl)

theorem SymbolicExprInfers.directCallExplicitSpecializes
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (selected : SourceWellFormed.SelectsFunction
      symbolic.scopeContext path scheme)
    (explicit : ExplicitGenericArgumentsRetain symbolic.globals path
      scheme.genericParameters symbolicSubstitution)
    (genericArguments : Static.SymbolicArgumentsBound symbolicSubstitution
      scheme.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution scheme.requirements)
    (parameters : Static.substituteTypes symbolicSubstitution scheme.parameterTypes =
      some symbolicParameterTypes)
    (arguments : ExprsCheckSpecialize outer concrete surfaceArguments
      symbolicParameterTypes)
    (parameterGrounds : Static.instantiateTypes outer symbolicParameterTypes =
      some resolved.parameterTypes)
    (returned : scheme.returnType.substitute symbolicSubstitution =
      some symbolicReturnType)
    (returnGrounds : symbolicReturnType.instantiate outer =
      some resolved.returnType)
    (artifact : FunctionArtifactDemand concrete path scheme groundTypeArguments
      groundConstArguments resolved)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
    ExprSpecializes outer concrete (.call (.path path) surfaceArguments)
      symbolicReturnType := by
  have parametersGround := genericArguments.parametersGround typeArgumentsGround
    constArgumentsGround
  obtain ⟨head, tail, found, explicitGrounds⟩ :=
    explicit.specializes contexts parametersGround
  have explicitGround : SurfaceElaboration.ExplicitCallArgumentsGround concrete
      path scheme.genericParameters
      (symbolicSubstitution.composeGround outer) := by
    unfold SurfaceElaboration.ExplicitCallArgumentsGround
    rw [found]
    exact explicitGrounds
  have resolvedCall := artifact.resolvesDirectCall contexts selected
    genericArguments typeArgumentsGround constArgumentsGround requirements
    parameters parameterGrounds returned returnGrounds explicitGround
  exact directCallSpecializes arguments parameterGrounds resolvedCall
    notIntrinsic returnGrounds

theorem SymbolicExprInfers.directCallInferredSpecializes
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (selected : SourceWellFormed.SelectsFunction
      symbolic.scopeContext path scheme)
    (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
    (genericArguments : Static.SymbolicArgumentsBound symbolicSubstitution
      scheme.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution scheme.requirements)
    (arguments : ExprsInferMatchedSpecialize outer concrete symbolic
      symbolicSubstitution surfaceArguments scheme.parameterTypes observedTypes)
    (argumentGrounds : Static.instantiateTypes outer observedTypes =
      some resolved.parameterTypes)
    (returned : scheme.returnType.substitute symbolicSubstitution =
      some symbolicReturnType)
    (returnGrounds : symbolicReturnType.instantiate outer =
      some resolved.returnType)
    (artifact : FunctionArtifactDemand concrete path scheme groundTypeArguments
      groundConstArguments resolved)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
    ExprSpecializes outer concrete (.call (.path path) surfaceArguments)
      symbolicReturnType := by
  have parameters := arguments.symbolicMatches.substitutes
  have explicitGround : SurfaceElaboration.ExplicitCallArgumentsGround concrete
      path scheme.genericParameters (symbolicSubstitution.composeGround outer) := by
    unfold SurfaceElaboration.ExplicitCallArgumentsGround
    rw [implicitArguments]
    trivial
  have resolvedCall := artifact.resolvesDirectCall contexts selected
    genericArguments typeArgumentsGround constArgumentsGround requirements
    parameters argumentGrounds returned returnGrounds explicitGround
  exact directCallSpecializes arguments.checkSpecializes argumentGrounds
    resolvedCall notIntrinsic returnGrounds

theorem SymbolicExprInfers.directCallNongenericSpecializes
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (selected : SourceWellFormed.SelectsFunction
      symbolic.scopeContext path scheme)
    (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
    (nongeneric : scheme.genericParameters = [])
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer {}
      scheme.requirements)
    (parametersClosed : Static.substituteTypes {} scheme.parameterTypes =
      some scheme.parameterTypes)
    (returnClosed : scheme.returnType.substitute {} = some scheme.returnType)
    (arguments : ExprsCheckSpecialize outer concrete surfaceArguments
      scheme.parameterTypes)
    (parameterGrounds : Static.instantiateTypes outer scheme.parameterTypes =
      some resolved.parameterTypes)
    (returnGrounds : scheme.returnType.instantiate outer =
      some resolved.returnType)
    (artifact : FunctionArtifactDemand concrete path scheme [] [] resolved)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
    ExprSpecializes outer concrete (.call (.path path) surfaceArguments)
      scheme.returnType := by
  have genericArguments : Static.SymbolicArgumentsBound {}
      scheme.genericParameters [] [] := by
    rw [nongeneric]
    exact .nil
  have explicitGround : SurfaceElaboration.ExplicitCallArgumentsGround concrete
      path scheme.genericParameters
      (({} : Static.SymbolicSubstitution).composeGround outer) := by
    unfold SurfaceElaboration.ExplicitCallArgumentsGround
    rw [implicitArguments]
    trivial
  have resolvedCall := artifact.resolvesDirectCall contexts selected
    genericArguments rfl rfl requirements
    parametersClosed parameterGrounds returnClosed returnGrounds explicitGround
  exact directCallSpecializes arguments parameterGrounds resolvedCall notIntrinsic
    returnGrounds

/-- One direct-call occurrence carries its declaration-wide symbolic decision
    and the exact finite function artifact used after grounding. The three
    constructors mirror the language's explicit-generic, inferred-generic,
    and nongeneric call rules instead of erasing their distinct elaboration
    behavior behind an unconstrained concrete call premise. -/
inductive DirectCallSpecializes
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext) :
    Surface.Path → List Surface.Expr → Static.Ty → Prop where
  | explicit
      (selected : SourceWellFormed.SelectsFunction
        symbolic.scopeContext path scheme)
      (explicitArguments : ExplicitGenericArgumentsRetain symbolic.globals path
        scheme.genericParameters inner)
      (genericArguments : Static.SymbolicArgumentsBound inner
        scheme.genericParameters symbolicTypeArguments symbolicConstArguments)
      (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
        some groundTypeArguments)
      (constArgumentsGround : Static.instantiateConstants outer
        symbolicConstArguments = some groundConstArguments)
      (parametersSubstitute : Static.substituteTypes inner scheme.parameterTypes =
        some symbolicParameterTypes)
      (arguments : SymbolicExprsCheckSpecialize outer concrete symbolic
        surfaceArguments symbolicParameterTypes)
      (requirements : Static.SymbolicRequirementsGround
        symbolic.globals.implementations symbolic.assumptions outer inner
        scheme.requirements)
      (returnSubstitute : scheme.returnType.substitute inner = some returnType)
      (parameterGrounds : Static.instantiateTypes outer symbolicParameterTypes =
        some resolved.parameterTypes)
      (returnGrounds : returnType.instantiate outer = some resolved.returnType)
      (artifact : FunctionArtifactDemand concrete path scheme groundTypeArguments
        groundConstArguments resolved)
      (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
      DirectCallSpecializes outer concrete symbolic path surfaceArguments returnType
  | inferred
      (selected : SourceWellFormed.SelectsFunction
        symbolic.scopeContext path scheme)
      (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
      (generic : scheme.genericParameters ≠ [])
      (determined : SurfaceElaboration.TypesDetermineGenericParameters
        scheme.parameterTypes scheme.genericParameters)
      (genericArguments : Static.SymbolicArgumentsBound inner
        scheme.genericParameters symbolicTypeArguments symbolicConstArguments)
      (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
        some groundTypeArguments)
      (constArgumentsGround : Static.instantiateConstants outer
        symbolicConstArguments = some groundConstArguments)
      (arguments : ExprsInferMatchedSpecialize outer concrete symbolic inner
        surfaceArguments scheme.parameterTypes observedTypes)
      (requirements : Static.SymbolicRequirementsGround
        symbolic.globals.implementations symbolic.assumptions outer inner
        scheme.requirements)
      (returnSubstitute : scheme.returnType.substitute inner = some returnType)
      (argumentGrounds : Static.instantiateTypes outer observedTypes =
        some resolved.parameterTypes)
      (returnGrounds : returnType.instantiate outer = some resolved.returnType)
      (artifact : FunctionArtifactDemand concrete path scheme groundTypeArguments
        groundConstArguments resolved)
      (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
      DirectCallSpecializes outer concrete symbolic path surfaceArguments returnType
  | nongeneric
      (selected : SourceWellFormed.SelectsFunction
        symbolic.scopeContext path scheme)
      (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
      (nongeneric : scheme.genericParameters = [])
      (requirements : Static.SymbolicRequirementsGround
        symbolic.globals.implementations symbolic.assumptions outer {}
        scheme.requirements)
      (parametersClosed : Static.substituteTypes {} scheme.parameterTypes =
        some scheme.parameterTypes)
      (returnClosed : scheme.returnType.substitute {} = some scheme.returnType)
      (arguments : SymbolicExprsCheckSpecialize outer concrete symbolic
        surfaceArguments scheme.parameterTypes)
      (parameterGrounds : Static.instantiateTypes outer scheme.parameterTypes =
        some resolved.parameterTypes)
      (returnGrounds : scheme.returnType.instantiate outer =
        some resolved.returnType)
      (artifact : FunctionArtifactDemand concrete path scheme [] [] resolved)
      (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
      DirectCallSpecializes outer concrete symbolic path surfaceArguments
        scheme.returnType

theorem DirectCallSpecializes.symbolic
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {path : Surface.Path}
    {surfaceArguments : List Surface.Expr}
    {returnType : Static.Ty}
    (specialized : DirectCallSpecializes outer concrete symbolic path
      surfaceArguments returnType) :
    SymbolicExprInfers symbolic (.call (.path path) surfaceArguments) returnType := by
  cases specialized with
  | explicit selected explicitArguments genericArguments typeArgumentsGround
      constArgumentsGround parametersSubstitute arguments requirements
      returnSubstitute parameterGrounds returnGrounds artifact notIntrinsic =>
      exact .directCallExplicit selected explicitArguments parametersSubstitute
        arguments.symbolicExpressions requirements.symbolic returnSubstitute
        notIntrinsic
  | inferred selected implicitArguments generic determined genericArguments
      typeArgumentsGround constArgumentsGround arguments requirements
      returnSubstitute argumentGrounds returnGrounds artifact notIntrinsic =>
      exact .directCallInferred selected implicitArguments generic determined
        arguments.symbolicExpressions arguments.symbolicMatches
        genericArguments.parametersBound requirements.symbolic returnSubstitute
        notIntrinsic
  | nongeneric selected implicitArguments nongeneric requirements parametersClosed
      returnClosed arguments parameterGrounds returnGrounds artifact notIntrinsic =>
      exact .directCallNongeneric selected implicitArguments nongeneric
        arguments.symbolicExpressions requirements.symbolic notIntrinsic

theorem DirectCallSpecializes.concrete
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {path : Surface.Path}
    {surfaceArguments : List Surface.Expr}
    {returnType : Static.Ty}
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (specialized : DirectCallSpecializes outer concrete symbolic path
      surfaceArguments returnType) :
    ExprSpecializes outer concrete (.call (.path path) surfaceArguments)
      returnType := by
  cases specialized with
  | explicit selected explicitArguments genericArguments typeArgumentsGround
      constArgumentsGround parametersSubstitute arguments requirements
      returnSubstitute parameterGrounds returnGrounds artifact notIntrinsic =>
      exact SymbolicExprInfers.directCallExplicitSpecializes contexts selected
        explicitArguments genericArguments typeArgumentsGround constArgumentsGround
        requirements parametersSubstitute arguments.concreteExpressions
        parameterGrounds returnSubstitute returnGrounds artifact notIntrinsic
  | inferred selected implicitArguments generic determined genericArguments
      typeArgumentsGround constArgumentsGround arguments requirements
      returnSubstitute argumentGrounds returnGrounds artifact notIntrinsic =>
      exact SymbolicExprInfers.directCallInferredSpecializes contexts selected
        implicitArguments genericArguments typeArgumentsGround constArgumentsGround
        requirements arguments argumentGrounds returnSubstitute returnGrounds
        artifact notIntrinsic
  | nongeneric selected implicitArguments nongeneric requirements parametersClosed
      returnClosed arguments parameterGrounds returnGrounds artifact notIntrinsic =>
      exact SymbolicExprInfers.directCallNongenericSpecializes contexts selected
        implicitArguments nongeneric requirements parametersClosed returnClosed
        arguments.concreteExpressions parameterGrounds returnGrounds artifact
        notIntrinsic

theorem SymbolicExprInfers.variantExplicitSpecializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
    (explicit : ExplicitGenericArgumentsRetain symbolic.globals path
      constructor.genericParameters symbolicSubstitution)
    (arguments : Static.SymbolicArgumentsBound symbolicSubstitution
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution constructor.requirements)
    (artifact : NominalArtifactDemand concrete constructor.nominalDeclaration
      constructor.sourceType .enumeration groundTypeArguments groundConstArguments
      resolved)
    (payload : ExprsSubstitutedCheckSpecialize outer concrete symbolic
      symbolicSubstitution surfaceArguments constructor.payload) :
    ExprSpecializes outer concrete (.call (.path path) surfaceArguments)
      (.nominal constructor.sourceType symbolicTypeArguments symbolicConstArguments) := by
  have parametersGround := arguments.parametersGround typeArgumentsGround
    constArgumentsGround
  have concreteArguments := explicit.specializes contexts parametersGround
  have instantiated := artifact.instantiates contexts arguments typeArgumentsGround
    constArgumentsGround requirements
  obtain ⟨coreArguments, payloadConcrete⟩ := payload.concrete
  have resolvedTypesGround :
      Static.instantiateTypes outer symbolicTypeArguments =
        some resolved.typeArguments := by
    rw [artifact.typeArguments]
    exact typeArgumentsGround
  have resolvedConstantsGround :
      Static.instantiateConstants outer symbolicConstArguments =
        some resolved.constArguments := by
    rw [artifact.constArguments]
    exact constArgumentsGround
  exact .intro
    (.nominal constructor.sourceType resolved.typeArguments resolved.constArguments)
    (.enumValue resolved.coreType constructor.variant coreArguments)
    (by simp [Static.Ty.instantiate, resolvedTypesGround, resolvedConstantsGround])
    (.variantCallExplicit (contexts.selectsVariantConstructor selected) notIntrinsic
      concreteArguments instantiated payloadConcrete)

theorem SymbolicExprInfers.variantInferredSpecializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
    (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
    (generic : constructor.genericParameters ≠ [])
    (determined : SurfaceElaboration.TypesDetermineGenericParameters
      constructor.payload constructor.genericParameters)
    (payload : ExprsInferMatchedSpecialize outer concrete symbolic
      symbolicSubstitution surfaceArguments constructor.payload observedTypes)
    (arguments : Static.SymbolicArgumentsBound symbolicSubstitution
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution constructor.requirements)
    (artifact : NominalArtifactDemand concrete constructor.nominalDeclaration
      constructor.sourceType .enumeration groundTypeArguments groundConstArguments
      resolved) :
    ExprSpecializes outer concrete (.call (.path path) surfaceArguments)
      (.nominal constructor.sourceType symbolicTypeArguments symbolicConstArguments) := by
  have instantiated := artifact.instantiates contexts arguments typeArgumentsGround
    constArgumentsGround requirements
  obtain ⟨coreArguments, payloadConcrete⟩ := payload.concrete
  have resolvedTypesGround :
      Static.instantiateTypes outer symbolicTypeArguments =
        some resolved.typeArguments := by
    rw [artifact.typeArguments]
    exact typeArgumentsGround
  have resolvedConstantsGround :
      Static.instantiateConstants outer symbolicConstArguments =
        some resolved.constArguments := by
    rw [artifact.constArguments]
    exact constArgumentsGround
  exact .intro
    (.nominal constructor.sourceType resolved.typeArguments resolved.constArguments)
    (.enumValue resolved.coreType constructor.variant coreArguments)
    (by simp [Static.Ty.instantiate, resolvedTypesGround, resolvedConstantsGround])
    (.variantCallInferred (contexts.selectsVariantConstructor selected) notIntrinsic
      implicitArguments generic determined payloadConcrete instantiated)

theorem SymbolicExprInfers.variantNongenericSpecializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
    (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
    (nongeneric : constructor.genericParameters = [])
    (payload : ExprsSubstitutedCheckSpecialize outer concrete symbolic
      symbolicSubstitution surfaceArguments constructor.payload)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution constructor.requirements)
    (artifact : NominalArtifactDemand concrete constructor.nominalDeclaration
      constructor.sourceType .enumeration [] [] resolved) :
    ExprSpecializes outer concrete (.call (.path path) surfaceArguments)
      (.nominal constructor.sourceType [] []) := by
  have noArguments : Static.SymbolicArgumentsBound symbolicSubstitution
      constructor.genericParameters [] [] := by
    rw [nongeneric]
    exact .nil
  have instantiated := artifact.instantiates contexts noArguments
    (by rfl) (by rfl) requirements
  obtain ⟨coreArguments, payloadConcrete⟩ := payload.concrete
  have resolvedTypes : resolved.typeArguments = [] := artifact.typeArguments
  have resolvedConstants : resolved.constArguments = [] := artifact.constArguments
  exact .intro
    (.nominal constructor.sourceType resolved.typeArguments resolved.constArguments)
    (.enumValue resolved.coreType constructor.variant coreArguments)
    (by simp [Static.Ty.instantiate, Static.instantiateTypes,
      Static.instantiateConstants, resolvedTypes, resolvedConstants])
    (.variantCallNongeneric (contexts.selectsVariantConstructor selected) notIntrinsic
      implicitArguments nongeneric instantiated payloadConcrete)

theorem SymbolicExprInfers.structExplicitSpecializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (selected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path constructor)
    (explicit : ExplicitGenericArgumentsRetain symbolic.globals path
      constructor.genericParameters symbolicSubstitution)
    (arguments : Static.SymbolicArgumentsBound symbolicSubstitution
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution constructor.requirements)
    (artifact : NominalArtifactDemand concrete constructor.declaration
      constructor.sourceType .structure groundTypeArguments groundConstArguments
      resolved)
    (fields : StructFieldsCheckSpecialize outer concrete symbolic
      symbolicSubstitution constructor.fields surfaceFields) :
    ExprSpecializes outer concrete (.structValue path surfaceFields)
      (.nominal constructor.sourceType symbolicTypeArguments symbolicConstArguments) := by
  have parametersGround := arguments.parametersGround typeArgumentsGround
    constArgumentsGround
  have concreteArguments := explicit.specializes contexts parametersGround
  have instantiated := artifact.instantiates contexts arguments typeArgumentsGround
    constArgumentsGround requirements
  obtain ⟨coreFields, fieldsConcrete⟩ := fields.concrete
  have resolvedTypesGround :
      Static.instantiateTypes outer symbolicTypeArguments =
        some resolved.typeArguments := by
    rw [artifact.typeArguments]
    exact typeArgumentsGround
  have resolvedConstantsGround :
      Static.instantiateConstants outer symbolicConstArguments =
        some resolved.constArguments := by
    rw [artifact.constArguments]
    exact constArgumentsGround
  exact .intro
    (.nominal constructor.sourceType resolved.typeArguments resolved.constArguments)
    (.structValue resolved.coreType coreFields)
    (by simp [Static.Ty.instantiate, resolvedTypesGround, resolvedConstantsGround])
    (.structValueExplicit (contexts.selectsStructConstructor selected)
      concreteArguments instantiated fieldsConcrete)

theorem SymbolicExprInfers.structInferredSpecializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (selected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path constructor)
    (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
    (generic : constructor.genericParameters ≠ [])
    (determined : SurfaceElaboration.TypesDetermineGenericParameters
      (constructor.fields.map fun field => field.type) constructor.genericParameters)
    (fields : StructFieldsInferMatchedSpecialize outer concrete symbolic
      symbolicSubstitution constructor.fields surfaceFields)
    (arguments : Static.SymbolicArgumentsBound symbolicSubstitution
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution constructor.requirements)
    (artifact : NominalArtifactDemand concrete constructor.declaration
      constructor.sourceType .structure groundTypeArguments groundConstArguments
      resolved) :
    ExprSpecializes outer concrete (.structValue path surfaceFields)
      (.nominal constructor.sourceType symbolicTypeArguments symbolicConstArguments) := by
  have instantiated := artifact.instantiates contexts arguments typeArgumentsGround
    constArgumentsGround requirements
  obtain ⟨coreFields, fieldsConcrete⟩ := fields.concrete
  have resolvedTypesGround :
      Static.instantiateTypes outer symbolicTypeArguments =
        some resolved.typeArguments := by
    rw [artifact.typeArguments]
    exact typeArgumentsGround
  have resolvedConstantsGround :
      Static.instantiateConstants outer symbolicConstArguments =
        some resolved.constArguments := by
    rw [artifact.constArguments]
    exact constArgumentsGround
  exact .intro
    (.nominal constructor.sourceType resolved.typeArguments resolved.constArguments)
    (.structValue resolved.coreType coreFields)
    (by simp [Static.Ty.instantiate, resolvedTypesGround, resolvedConstantsGround])
    (.structValueInferred (contexts.selectsStructConstructor selected)
      implicitArguments generic determined fieldsConcrete instantiated)

theorem SymbolicExprInfers.structNongenericSpecializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (selected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path constructor)
    (implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path)
    (nongeneric : constructor.genericParameters = [])
    (fields : StructFieldsCheckSpecialize outer concrete symbolic
      symbolicSubstitution constructor.fields surfaceFields)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution constructor.requirements)
    (artifact : NominalArtifactDemand concrete constructor.declaration
      constructor.sourceType .structure [] [] resolved) :
    ExprSpecializes outer concrete (.structValue path surfaceFields)
      (.nominal constructor.sourceType [] []) := by
  have noArguments : Static.SymbolicArgumentsBound symbolicSubstitution
      constructor.genericParameters [] [] := by
    rw [nongeneric]
    exact .nil
  have instantiated := artifact.instantiates contexts noArguments
    (by rfl) (by rfl) requirements
  obtain ⟨coreFields, fieldsConcrete⟩ := fields.concrete
  have resolvedTypes : resolved.typeArguments = [] := artifact.typeArguments
  have resolvedConstants : resolved.constArguments = [] := artifact.constArguments
  exact .intro
    (.nominal constructor.sourceType resolved.typeArguments resolved.constArguments)
    (.structValue resolved.coreType coreFields)
    (by simp [Static.Ty.instantiate, Static.instantiateTypes,
      Static.instantiateConstants, resolvedTypes, resolvedConstants])
    (.structValueNongeneric (contexts.selectsStructConstructor selected)
      implicitArguments nongeneric instantiated fieldsConcrete)

theorem SymbolicExprChecks.structValueSpecializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (selected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path constructor)
    (expected : expectedType = .nominal constructor.sourceType
      symbolicTypeArguments symbolicConstArguments)
    (arguments : Static.SymbolicArgumentsBound symbolicSubstitution
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (pathArguments : SymbolicPathArgumentsCompatible symbolic.globals path
      constructor.genericParameters symbolicSubstitution)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution constructor.requirements)
    (artifact : NominalArtifactDemand concrete constructor.declaration
      constructor.sourceType .structure groundTypeArguments groundConstArguments
      resolved)
    (fields : StructFieldsCheckSpecialize outer concrete symbolic
      symbolicSubstitution constructor.fields surfaceFields) :
    ExprCheckSpecializes outer concrete (.structValue path surfaceFields)
      expectedType := by
  have parametersGround := arguments.parametersGround typeArgumentsGround
    constArgumentsGround
  have concretePath := pathArguments.specializes contexts parametersGround
  have instantiated := artifact.instantiates contexts arguments typeArgumentsGround
    constArgumentsGround requirements
  obtain ⟨coreFields, fieldsConcrete⟩ := fields.concrete
  have resolvedTypesGround :
      Static.instantiateTypes outer symbolicTypeArguments =
        some resolved.typeArguments := by
    rw [artifact.typeArguments]
    exact typeArgumentsGround
  have resolvedConstantsGround :
      Static.instantiateConstants outer symbolicConstArguments =
        some resolved.constArguments := by
    rw [artifact.constArguments]
    exact constArgumentsGround
  exact .intro
    (.nominal constructor.sourceType resolved.typeArguments resolved.constArguments)
    (.structValue resolved.coreType coreFields)
    (by rw [expected]; simp [Static.Ty.instantiate, resolvedTypesGround,
      resolvedConstantsGround])
    (.structValue (contexts.selectsStructConstructor selected) concretePath
      instantiated rfl fieldsConcrete)

theorem SymbolicExprChecks.variantCallSpecializes
    {symbolic : SymbolicBodyContext}
    {outer : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturnType concrete)
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
    (expected : expectedType = .nominal constructor.sourceType
      symbolicTypeArguments symbolicConstArguments)
    (arguments : Static.SymbolicArgumentsBound symbolicSubstitution
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer symbolicConstArguments =
      some groundConstArguments)
    (pathArguments : SymbolicPathArgumentsCompatible symbolic.globals path
      constructor.genericParameters symbolicSubstitution)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer
      symbolicSubstitution constructor.requirements)
    (artifact : NominalArtifactDemand concrete constructor.nominalDeclaration
      constructor.sourceType .enumeration groundTypeArguments groundConstArguments
      resolved)
    (payload : ExprsSubstitutedCheckSpecialize outer concrete symbolic
      symbolicSubstitution surfaceArguments constructor.payload) :
    ExprCheckSpecializes outer concrete (.call (.path path) surfaceArguments)
      expectedType := by
  have parametersGround := arguments.parametersGround typeArgumentsGround
    constArgumentsGround
  have concretePath := pathArguments.specializes contexts parametersGround
  have instantiated := artifact.instantiates contexts arguments typeArgumentsGround
    constArgumentsGround requirements
  obtain ⟨coreArguments, payloadConcrete⟩ := payload.concrete
  have resolvedTypesGround :
      Static.instantiateTypes outer symbolicTypeArguments =
        some resolved.typeArguments := by
    rw [artifact.typeArguments]
    exact typeArgumentsGround
  have resolvedConstantsGround :
      Static.instantiateConstants outer symbolicConstArguments =
        some resolved.constArguments := by
    rw [artifact.constArguments]
    exact constArgumentsGround
  exact .intro
    (.nominal constructor.sourceType resolved.typeArguments resolved.constArguments)
    (.enumValue resolved.coreType constructor.variant coreArguments)
    (by rw [expected]; simp [Static.Ty.instantiate, resolvedTypesGround,
      resolvedConstantsGround])
    (.variantCall (contexts.selectsVariantConstructor selected) notIntrinsic
      concretePath instantiated rfl payloadConcrete)

theorem SymbolicExprInfers.indexArraySpecializes
    (base : ExprSpecializes substitution concrete surfaceBase
      (.array elementType length))
    (index : ExprSpecializes substitution concrete surfaceIndex indexType)
    (integer : SymbolicIntegerType indexType) :
    ExprSpecializes substitution concrete
      (.index surfaceBase surfaceIndex) elementType := by
  cases base with
  | intro baseGround coreBase baseGrounds baseLowers =>
      cases elementGrounds : elementType.instantiate substitution with
      | none =>
          simp [Static.Ty.instantiate, elementGrounds] at baseGrounds
      | some groundElement =>
          cases lengthGrounds : length.instantiate substitution with
          | none =>
              simp [Static.Ty.instantiate, elementGrounds, lengthGrounds]
                at baseGrounds
          | some groundLength =>
              simp [Static.Ty.instantiate, elementGrounds, lengthGrounds]
                at baseGrounds
              subst baseGround
              cases index with
              | intro indexGround coreIndex indexGrounds indexLowers =>
                  obtain ⟨coreIndexType, indexCore, coreInteger⟩ :=
                    integer.specializes indexGrounds
                  exact .intro groundElement (.index coreBase coreIndex)
                    elementGrounds
                    (.indexArray baseLowers indexLowers indexCore coreInteger)

theorem SymbolicExprInfers.indexSliceSpecializes
    (base : ExprSpecializes substitution concrete surfaceBase
      (.slice elementType))
    (index : ExprSpecializes substitution concrete surfaceIndex indexType)
    (integer : SymbolicIntegerType indexType) :
    ExprSpecializes substitution concrete
      (.index surfaceBase surfaceIndex) elementType := by
  cases base with
  | intro baseGround coreBase baseGrounds baseLowers =>
      cases elementGrounds : elementType.instantiate substitution with
      | none =>
          simp [Static.Ty.instantiate, elementGrounds] at baseGrounds
      | some groundElement =>
          simp [Static.Ty.instantiate, elementGrounds] at baseGrounds
          subst baseGround
          cases index with
          | intro indexGround coreIndex indexGrounds indexLowers =>
              obtain ⟨coreIndexType, indexCore, coreInteger⟩ :=
                integer.specializes indexGrounds
              exact .intro groundElement (.index coreBase coreIndex)
                elementGrounds
                (.indexSlice baseLowers indexLowers indexCore coreInteger)

theorem SymbolicPlaceHasType.localSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (single : SurfaceElaboration.singleNamePath? path = some name)
    (resolved : ResolvesSymbolicLocal symbolic.locals name binding) :
    PlaceSpecializes substitution concrete (.path path) binding.type := by
  obtain ⟨concreteBinding, concreteResolved, typeGrounds⟩ :=
    specialized.locals.forward name binding resolved
  exact .intro concreteBinding.type (.local concreteBinding.id) typeGrounds
    (.local name single concreteResolved)

theorem SymbolicPlaceHasType.selfSpecializes
    {symbolic : SymbolicBodyContext}
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (specialized : symbolic.Specializes substitution groundReturnType concrete)
    (resolved : ResolvesSymbolicLocal symbolic.locals "self" binding) :
    PlaceSpecializes substitution concrete .selfValue binding.type := by
  obtain ⟨concreteBinding, concreteResolved, typeGrounds⟩ :=
    specialized.locals.forward "self" binding resolved
  exact .intro concreteBinding.type (.local concreteBinding.id) typeGrounds
    (.selfValue concreteResolved)

theorem SymbolicPlaceHasType.indexArraySpecializes
    (base : PlaceSpecializes substitution concrete surfaceBase
      (.array elementType length))
    (index : ExprSpecializes substitution concrete surfaceIndex indexType)
    (integer : SymbolicIntegerType indexType) :
    PlaceSpecializes substitution concrete
      (.index surfaceBase surfaceIndex) elementType := by
  cases base with
  | intro baseGround coreBase baseGrounds baseLowers =>
      cases elementGrounds : elementType.instantiate substitution with
      | none =>
          simp [Static.Ty.instantiate, elementGrounds] at baseGrounds
      | some groundElement =>
          cases lengthGrounds : length.instantiate substitution with
          | none =>
              simp [Static.Ty.instantiate, elementGrounds, lengthGrounds]
                at baseGrounds
          | some groundLength =>
              simp [Static.Ty.instantiate, elementGrounds, lengthGrounds]
                at baseGrounds
              subst baseGround
              cases index with
              | intro indexGround coreIndex indexGrounds indexLowers =>
                  obtain ⟨coreIndexType, indexCore, coreInteger⟩ :=
                    integer.specializes indexGrounds
                  exact .intro groundElement (.index coreBase coreIndex)
                    elementGrounds
                    (.indexArray baseLowers indexLowers indexCore coreInteger)

theorem SymbolicPlaceHasType.indexSliceSpecializes
    (base : PlaceSpecializes substitution concrete surfaceBase
      (.slice elementType))
    (index : ExprSpecializes substitution concrete surfaceIndex indexType)
    (integer : SymbolicIntegerType indexType) :
    PlaceSpecializes substitution concrete
      (.index surfaceBase surfaceIndex) elementType := by
  cases base with
  | intro baseGround coreBase baseGrounds baseLowers =>
      cases elementGrounds : elementType.instantiate substitution with
      | none =>
          simp [Static.Ty.instantiate, elementGrounds] at baseGrounds
      | some groundElement =>
          simp [Static.Ty.instantiate, elementGrounds] at baseGrounds
          subst baseGround
          cases index with
          | intro indexGround coreIndex indexGrounds indexLowers =>
              obtain ⟨coreIndexType, indexCore, coreInteger⟩ :=
                integer.specializes indexGrounds
              exact .intro groundElement (.index coreBase coreIndex)
                elementGrounds
                (.indexSlice baseLowers indexLowers indexCore coreInteger)

/-- Specialization of the implicit member-access dereference. The symbolic
    judgment decides whether one immutable reference layer is removed; this
    witness records the corresponding ground receiver and core expression. -/
inductive MemberBaseSpecializes
    (substitution : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (surface : Surface.Expr) (sourceType receiverType : Static.Ty) :
    Static.GroundTy → Core.Expr → Prop where
  | intro
      (sourceGround : Static.GroundTy)
      (sourceCore : Core.Expr)
      (sourceGrounds : sourceType.instantiate substitution = some sourceGround)
      (receiverGrounds : receiverType.instantiate substitution = some receiverGround)
      (sourceLowers : SurfaceElaboration.ExprLowers concrete surface
        sourceGround sourceCore)
      (memberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
        sourceGround sourceCore receiverGround receiverCore) :
      MemberBaseSpecializes substitution concrete surface sourceType receiverType
        receiverGround receiverCore

theorem SymbolicMemberBase.specializes
    (base : ExprSpecializes substitution concrete surface sourceType)
    (member : SymbolicMemberBase sourceType receiverType) :
    ∃ receiverGround receiverCore,
      MemberBaseSpecializes substitution concrete surface sourceType receiverType
        receiverGround receiverCore := by
  cases base with
  | intro sourceGround sourceCore sourceGrounds sourceLowers =>
      cases sourceType with
      | unit =>
          simp [SymbolicMemberBase] at member
          subst receiverType
          exact ⟨sourceGround, sourceCore,
            .intro sourceGround sourceCore sourceGrounds sourceGrounds
              sourceLowers .direct⟩
      | scalar scalarType =>
          simp [SymbolicMemberBase] at member
          subst receiverType
          exact ⟨sourceGround, sourceCore,
            .intro sourceGround sourceCore sourceGrounds sourceGrounds
              sourceLowers .direct⟩
      | parameter parameter =>
          simp [SymbolicMemberBase] at member
          subst receiverType
          exact ⟨sourceGround, sourceCore,
            .intro sourceGround sourceCore sourceGrounds sourceGrounds
              sourceLowers .direct⟩
      | array element length =>
          simp [SymbolicMemberBase] at member
          subst receiverType
          exact ⟨sourceGround, sourceCore,
            .intro sourceGround sourceCore sourceGrounds sourceGrounds
              sourceLowers .direct⟩
      | slice element =>
          simp [SymbolicMemberBase] at member
          subst receiverType
          exact ⟨sourceGround, sourceCore,
            .intro sourceGround sourceCore sourceGrounds sourceGrounds
              sourceLowers .direct⟩
      | reference referent =>
          simp [SymbolicMemberBase] at member
          subst receiverType
          cases referentGrounded : referent.instantiate substitution with
          | none =>
              simp [Static.Ty.instantiate, referentGrounded] at sourceGrounds
          | some groundReferent =>
              simp [Static.Ty.instantiate, referentGrounded] at sourceGrounds
              subst sourceGround
              exact ⟨groundReferent, .dereference sourceCore,
                .intro (.reference groundReferent) sourceCore
                  (by simp [Static.Ty.instantiate, referentGrounded])
                  referentGrounded sourceLowers (.reference .direct)⟩
      | nominal typeId typeArguments constArguments =>
          simp [SymbolicMemberBase] at member
          subst receiverType
          exact ⟨sourceGround, sourceCore,
            .intro sourceGround sourceCore sourceGrounds sourceGrounds
              sourceLowers .direct⟩

/-- Field metadata is an occurrence-specific catalog obligation. Once the
    selected row is known to ground the symbolic result type, member-base
    specialization composes without any further catalog assumptions. -/
theorem SymbolicExprInfers.fieldSpecializes
    (member : MemberBaseSpecializes substitution concrete surfaceBase
      sourceReceiver receiverType groundReceiver coreBase)
    (selected : SurfaceElaboration.SelectsField concrete groundReceiver name entry)
    (fieldGrounds : fieldType.instantiate substitution = some entry.type) :
    ExprSpecializes substitution concrete (.member surfaceBase name) fieldType := by
  cases member with
  | intro sourceGround sourceCore sourceGrounds receiverGrounds sourceLowers
      memberLowers =>
      exact .intro entry.type (.field coreBase entry.field) fieldGrounds
        (.field sourceLowers memberLowers selected)

/-- Method specialization preserves the declaration chosen during symbolic
    typing, uses finite-table coherence to keep it the unique ground lookup,
    derives the emitted instance from substitution, and only then constructs
    the ordinary core call. No opaque concrete method-lowering witness remains. -/
theorem SymbolicExprInfers.methodCallSpecializes
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (member : MemberBaseSpecializes outer concrete surfaceReceiver
      sourceReceiver receiverType groundReceiver coreReceiver)
    (schemeMember : scheme ∈ symbolic.globals.methods)
    (schemeName : scheme.name = name)
    (memberMode : scheme.receiverMode ≠ .none)
    (genericArguments : Static.SymbolicArgumentsBound inner
      scheme.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer
      symbolicConstArguments = some groundConstArguments)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer inner
      scheme.requirements)
    (receiverSubstitute : scheme.receiverType.substitute inner =
      some receiverType)
    (argumentsSubstitute : Static.substituteTypes inner scheme.argumentTypes =
      some symbolicArgumentTypes)
    (arguments : ExprsCheckSpecialize outer concrete surfaceArguments
      symbolicArgumentTypes)
    (argumentGrounds : Static.instantiateTypes outer symbolicArgumentTypes =
      some groundArgumentTypes)
    (returnSubstitute : scheme.returnType.substitute inner = some symbolicResult)
    (resultGrounds : symbolicResult.instantiate outer = some groundResult)
    (artifact : MethodArtifactDemand concrete scheme groundTypeArguments
      groundConstArguments resolved)
    (resolvedReceiver : resolved.receiverType = groundReceiver)
    (resolvedArguments : resolved.argumentTypes = groundArgumentTypes)
    (resolvedResult : resolved.returnType = groundResult)
    (groundPreferred : scheme.preferredAt concrete.methods
      concrete.currentModule
      (Static.GroundMethodLookupApplicable concrete.implementations
        concrete.methodInstances groundReceiver name))
    (coherent : Static.MethodLookupCoherent concrete.implementations
      concrete.methods concrete.methodInstances)
    (receiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization resolved.receiverMode groundReceiver coreReceiver
      coreReceiverArgument) :
    ExprSpecializes outer concrete
      (.call (.member surfaceReceiver name) surfaceArguments) symbolicResult := by
  cases member with
  | intro sourceGround sourceCore sourceGrounds receiverGrounds sourceLowers
      memberLowers =>
      obtain ⟨actualGroundArguments, coreArguments, actualArgumentsGround,
        concreteArguments⟩ := arguments.checks
      rw [argumentGrounds] at actualArgumentsGround
      have groundArgumentsEquality := Option.some.inj actualArgumentsGround
      subst actualGroundArguments
      have resolvedMethod := artifact.resolvesMethod contexts schemeMember
        schemeName memberMode genericArguments typeArgumentsGround constArgumentsGround
        requirements receiverSubstitute receiverGrounds argumentsSubstitute
        argumentGrounds returnSubstitute resultGrounds resolvedReceiver
        resolvedArguments resolvedResult groundPreferred coherent
      have instantiated : Static.MethodInstantiates concrete.implementations
          scheme (inner.composeGround outer) resolved := by
        have receiverGroundResolved := receiverGrounds.trans
          (congrArg some resolvedReceiver.symm)
        have argumentsGroundResolved := argumentGrounds.trans
          (congrArg some resolvedArguments.symm)
        have resultGroundResolved := resultGrounds.trans
          (congrArg some resolvedResult.symm)
        exact artifact.instantiates contexts genericArguments typeArgumentsGround
          constArgumentsGround requirements receiverSubstitute
          receiverGroundResolved argumentsSubstitute argumentsGroundResolved
          returnSubstitute resultGroundResolved
      have resolvedName : resolved.name = name :=
        instantiated.signature.2.2.2.2.1.trans schemeName
      have lowered : Elaboration.MethodCallLowers concrete.implementations
          concrete.methods concrete.methodInstances concrete.currentModule
          concrete.monomorphization coreReceiver groundReceiver name coreArguments groundArgumentTypes
          resolved.returnType
          (.call resolved.function (coreReceiverArgument :: coreArguments)) :=
        .call scheme resolved resolvedMethod (inner.composeGround outer)
          instantiated resolvedReceiver resolvedName resolvedArguments
          coreReceiverArgument receiverArgument
      have resultGroundResolved : symbolicResult.instantiate outer =
          some resolved.returnType :=
        resultGrounds.trans (congrArg some resolvedResult.symm)
      exact .intro resolved.returnType
        (.call resolved.function (coreReceiverArgument :: coreArguments))
        resultGroundResolved
        (.methodCall sourceLowers memberLowers concreteArguments lowered)

/-- One method-call occurrence, from its symbolic typing decision through the
    exact finite monomorphic artifact used by concrete lowering. The relation
    exposes only evidence for the source occurrence being specialized; it does
    not quantify over hypothetical expressions or permit an unrelated concrete
    method selection to be supplied alongside the symbolic one. -/
inductive MethodCallSpecializes
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext) :
    Surface.Expr → Static.Ty → Static.Ty → Surface.Name →
      List Surface.Expr → Static.Ty → Prop where
  | inferred
      (receiver : SymbolicExprInfers symbolic surfaceReceiver sourceReceiver)
      (memberBase : SymbolicMemberBase sourceReceiver receiverType)
      (member : MemberBaseSpecializes outer concrete surfaceReceiver
        sourceReceiver receiverType groundReceiver coreReceiver)
      (schemeMember : scheme ∈ symbolic.globals.methods)
      (schemeName : scheme.name = name)
      (memberMode : scheme.receiverMode ≠ .none)
      (genericArguments : Static.SymbolicArgumentsBound inner
        scheme.genericParameters symbolicTypeArguments symbolicConstArguments)
      (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
        some groundTypeArguments)
      (constArgumentsGround : Static.instantiateConstants outer
        symbolicConstArguments = some groundConstArguments)
      (receiverMatch : Static.TySymbolicallyMatches inner
        scheme.receiverType receiverType)
      (arguments : ExprsInferMatchedSpecialize outer concrete symbolic inner
        surfaceArguments scheme.argumentTypes argumentTypes)
      (determined : SurfaceElaboration.TypesDetermineGenericParameters
        (scheme.receiverType :: scheme.argumentTypes) scheme.genericParameters)
      (requirements : Static.SymbolicRequirementsGround
        symbolic.globals.implementations symbolic.assumptions outer inner
        scheme.requirements)
      (returnSubstitute : scheme.returnType.substitute inner = some returnType)
      (symbolicPreferred : scheme.preferredAt symbolic.globals.methods
        symbolic.globals.currentModule
        (SymbolicMethodLookupApplicable symbolic receiverType name))
      (resultGrounds : returnType.instantiate outer = some groundResult)
      (argumentGrounds : Static.instantiateTypes outer argumentTypes =
        some groundArgumentTypes)
      (artifact : MethodArtifactDemand concrete scheme groundTypeArguments
        groundConstArguments resolved)
      (resolvedReceiver : resolved.receiverType = groundReceiver)
      (resolvedArguments : resolved.argumentTypes = groundArgumentTypes)
      (resolvedResult : resolved.returnType = groundResult)
      (groundPreferred : scheme.preferredAt concrete.methods
        concrete.currentModule
        (Static.GroundMethodLookupApplicable concrete.implementations
          concrete.methodInstances groundReceiver name))
      (coherent : Static.MethodLookupCoherent concrete.implementations
        concrete.methods concrete.methodInstances)
      (receiverArgument : Elaboration.ReceiverArgumentLowers
        concrete.monomorphization resolved.receiverMode groundReceiver
        coreReceiver coreReceiverArgument)
      (unique : ∀ candidate,
        candidate ∈ symbolic.globals.methods →
        SymbolicMethodLookupApplicable symbolic receiverType name candidate →
        candidate.preferredAt symbolic.globals.methods
          symbolic.globals.currentModule
          (SymbolicMethodLookupApplicable symbolic receiverType name) →
        candidate.declaration = scheme.declaration) :
      MethodCallSpecializes outer concrete symbolic surfaceReceiver
        sourceReceiver receiverType name surfaceArguments returnType
  | contextual
      (receiver : SymbolicExprInfers symbolic surfaceReceiver sourceReceiver)
      (memberBase : SymbolicMemberBase sourceReceiver receiverType)
      (member : MemberBaseSpecializes outer concrete surfaceReceiver
        sourceReceiver receiverType groundReceiver coreReceiver)
      (schemeMember : scheme ∈ symbolic.globals.methods)
      (schemeName : scheme.name = name)
      (memberMode : scheme.receiverMode ≠ .none)
      (genericArguments : Static.SymbolicArgumentsBound inner
        scheme.genericParameters symbolicTypeArguments symbolicConstArguments)
      (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
        some groundTypeArguments)
      (constArgumentsGround : Static.instantiateConstants outer
        symbolicConstArguments = some groundConstArguments)
      (receiverMatch : Static.TySymbolicallyMatches inner
        scheme.receiverType receiverType)
      (symbolicPreferred : scheme.preferredAt symbolic.globals.methods
        symbolic.globals.currentModule
        (SymbolicMethodLookupApplicable symbolic receiverType name))
      (determined : SurfaceElaboration.TypesDetermineGenericParameters
        [scheme.receiverType] scheme.genericParameters)
      (requirements : Static.SymbolicRequirementsGround
        symbolic.globals.implementations symbolic.assumptions outer inner
        scheme.requirements)
      (argumentsSubstitute : Static.substituteTypes inner scheme.argumentTypes =
        some expectedArgumentTypes)
      (arguments : SymbolicExprsCheckSpecialize outer concrete symbolic
        surfaceArguments expectedArgumentTypes)
      (returnSubstitute : scheme.returnType.substitute inner = some returnType)
      (resultGrounds : returnType.instantiate outer = some groundResult)
      (argumentGrounds : Static.instantiateTypes outer expectedArgumentTypes =
        some groundArgumentTypes)
      (artifact : MethodArtifactDemand concrete scheme groundTypeArguments
        groundConstArguments resolved)
      (resolvedReceiver : resolved.receiverType = groundReceiver)
      (resolvedArguments : resolved.argumentTypes = groundArgumentTypes)
      (resolvedResult : resolved.returnType = groundResult)
      (groundPreferred : scheme.preferredAt concrete.methods
        concrete.currentModule
        (Static.GroundMethodLookupApplicable concrete.implementations
          concrete.methodInstances groundReceiver name))
      (coherent : Static.MethodLookupCoherent concrete.implementations
        concrete.methods concrete.methodInstances)
      (receiverArgument : Elaboration.ReceiverArgumentLowers
        concrete.monomorphization resolved.receiverMode groundReceiver
        coreReceiver coreReceiverArgument)
      (unique : ∀ candidate,
        candidate ∈ symbolic.globals.methods →
        SymbolicMethodLookupApplicable symbolic receiverType name candidate →
        candidate.preferredAt symbolic.globals.methods
          symbolic.globals.currentModule
          (SymbolicMethodLookupApplicable symbolic receiverType name) →
        candidate.declaration = scheme.declaration) :
      MethodCallSpecializes outer concrete symbolic surfaceReceiver
        sourceReceiver receiverType name surfaceArguments returnType

theorem MethodCallSpecializes.symbolic
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {surfaceReceiver : Surface.Expr}
    {sourceReceiver receiverType : Static.Ty}
    {name : Surface.Name}
    {surfaceArguments : List Surface.Expr}
    {returnType : Static.Ty}
    (specialized : MethodCallSpecializes outer concrete symbolic surfaceReceiver
      sourceReceiver receiverType name surfaceArguments returnType) :
    SymbolicExprInfers symbolic
      (.call (.member surfaceReceiver name) surfaceArguments) returnType := by
  cases specialized with
  | inferred receiver memberBase member schemeMember schemeName memberMode genericArguments
      typeArgumentsGround constArgumentsGround receiverMatch arguments
      determined requirements returnSubstitute symbolicPreferred resultGrounds
      argumentGrounds artifact resolvedReceiver resolvedArguments resolvedResult
      groundPreferred coherent receiverArgument unique =>
      exact .methodCall receiver memberBase arguments.symbolicExpressions
        ⟨_, _, schemeMember, schemeName, memberMode, receiverMatch,
          arguments.symbolicMatches, determined,
          genericArguments.parametersBound,
          requirements.symbolic, returnSubstitute, symbolicPreferred, unique⟩
  | contextual receiver memberBase member schemeMember schemeName memberMode genericArguments
      typeArgumentsGround constArgumentsGround receiverMatch symbolicPreferred
      determined requirements argumentsSubstitute arguments returnSubstitute
      resultGrounds argumentGrounds artifact resolvedReceiver resolvedArguments
      resolvedResult groundPreferred coherent receiverArgument unique =>
      exact .methodCallContextual receiver memberBase
        ⟨⟨schemeMember, schemeName, memberMode, receiverMatch,
          genericArguments.parametersBound, requirements.symbolic,
          argumentsSubstitute, returnSubstitute⟩, symbolicPreferred, determined,
          unique⟩
        arguments.symbolicExpressions

theorem MethodCallSpecializes.concrete
    {outer : Static.Substitution}
    {concrete : SurfaceElaboration.Context}
    {symbolic : SymbolicBodyContext}
    {surfaceReceiver : Surface.Expr}
    {sourceReceiver receiverType : Static.Ty}
    {name : Surface.Name}
    {surfaceArguments : List Surface.Expr}
    {returnType : Static.Ty}
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (specialized : MethodCallSpecializes outer concrete symbolic surfaceReceiver
      sourceReceiver receiverType name surfaceArguments returnType) :
    ExprSpecializes outer concrete
      (.call (.member surfaceReceiver name) surfaceArguments) returnType := by
  cases specialized with
  | inferred receiver memberBase member schemeMember schemeName memberMode genericArguments
      typeArgumentsGround constArgumentsGround receiverMatch arguments
      determined requirements returnSubstitute symbolicPreferred resultGrounds
      argumentGrounds artifact resolvedReceiver resolvedArguments resolvedResult
      groundPreferred coherent receiverArgument unique =>
      exact SymbolicExprInfers.methodCallSpecializes contexts member schemeMember
        schemeName memberMode genericArguments typeArgumentsGround constArgumentsGround
        requirements receiverMatch.substitutes arguments.symbolicMatches.substitutes
        arguments.checkSpecializes argumentGrounds returnSubstitute resultGrounds
        artifact resolvedReceiver resolvedArguments resolvedResult groundPreferred
        coherent receiverArgument
  | contextual receiver memberBase member schemeMember schemeName memberMode genericArguments
      typeArgumentsGround constArgumentsGround receiverMatch symbolicPreferred
      determined requirements argumentsSubstitute arguments returnSubstitute
      resultGrounds argumentGrounds artifact resolvedReceiver resolvedArguments
      resolvedResult groundPreferred coherent receiverArgument unique =>
      exact SymbolicExprInfers.methodCallSpecializes contexts member schemeMember
        schemeName memberMode genericArguments typeArgumentsGround constArgumentsGround
        requirements receiverMatch.substitutes argumentsSubstitute
        arguments.concreteExpressions argumentGrounds returnSubstitute resultGrounds
        artifact resolvedReceiver resolvedArguments resolvedResult groundPreferred
        coherent receiverArgument

/-- Non-recursive evidence attached to one inferred generic direct call. Child
    expression traversal is deliberately absent: the recursive specialization
    relation owns that traversal and supplies the exact observed argument
    types and core expressions. -/
structure DirectCallInferenceEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path : Surface.Path)
    (observedTypes : List Static.Ty)
    (returnType : Static.Ty)
    (scheme : Static.FunctionScheme)
    (inner : Static.SymbolicSubstitution)
    (resolved : Static.FunctionInstance) : Type where
  symbolicTypeArguments : List Static.Ty
  symbolicConstArguments : List Static.Const
  groundTypeArguments : List Static.GroundTy
  groundConstArguments : List Nat
  selected : SourceWellFormed.SelectsFunction symbolic.scopeContext path scheme
  implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path
  generic : scheme.genericParameters ≠ []
  determined : SurfaceElaboration.TypesDetermineGenericParameters
    scheme.parameterTypes scheme.genericParameters
  genericArguments : Static.SymbolicArgumentsBound inner
    scheme.genericParameters symbolicTypeArguments symbolicConstArguments
  typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
    some groundTypeArguments
  constArgumentsGround : Static.instantiateConstants outer
    symbolicConstArguments = some groundConstArguments
  argumentMatches : Static.TypesSymbolicallyMatch inner
    scheme.parameterTypes observedTypes
  requirements : Static.SymbolicRequirementsGround
    symbolic.globals.implementations symbolic.assumptions outer inner
    scheme.requirements
  returnSubstitute : scheme.returnType.substitute inner = some returnType
  argumentGrounds : Static.instantiateTypes outer observedTypes =
    some resolved.parameterTypes
  returnGrounds : returnType.instantiate outer = some resolved.returnType
  artifact : FunctionArtifactDemand concrete path scheme groundTypeArguments
    groundConstArguments resolved
  notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none

theorem DirectCallInferenceEvidence.symbolicInference
    (evidence : DirectCallInferenceEvidence outer concrete symbolic path
      observedTypes returnType scheme inner resolved)
    (arguments : SymbolicExprsInfer symbolic surfaceArguments observedTypes) :
    SymbolicExprInfers symbolic (.call (.path path) surfaceArguments) returnType := by
  exact .directCallInferred evidence.selected evidence.implicitArguments
    evidence.generic evidence.determined arguments evidence.argumentMatches
    evidence.genericArguments.parametersBound evidence.requirements.symbolic
    evidence.returnSubstitute evidence.notIntrinsic

theorem DirectCallInferenceEvidence.concreteSpecialization
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : DirectCallInferenceEvidence outer concrete symbolic path
      observedTypes returnType scheme inner resolved)
    (arguments : ExprsInferMatchedSpecialize outer concrete symbolic inner
      surfaceArguments scheme.parameterTypes observedTypes) :
    ExprSpecializes outer concrete (.call (.path path) surfaceArguments)
      returnType := by
  exact SymbolicExprInfers.directCallInferredSpecializes contexts evidence.selected
    evidence.implicitArguments evidence.genericArguments
    evidence.typeArgumentsGround evidence.constArgumentsGround
    evidence.requirements arguments evidence.argumentGrounds
    evidence.returnSubstitute evidence.returnGrounds evidence.artifact
    evidence.notIntrinsic

theorem DirectCallInferenceEvidence.resolvesDirectCall
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : DirectCallInferenceEvidence outer concrete symbolic path
      observedTypes returnType scheme inner resolved) :
    SurfaceElaboration.ResolvesDirectCall concrete path resolved.parameterTypes
      scheme resolved := by
  have explicitGround : SurfaceElaboration.ExplicitCallArgumentsGround concrete
      path scheme.genericParameters (inner.composeGround outer) := by
    unfold SurfaceElaboration.ExplicitCallArgumentsGround
    rw [evidence.implicitArguments]
    trivial
  exact evidence.artifact.resolvesDirectCall contexts evidence.selected
    evidence.genericArguments evidence.typeArgumentsGround
    evidence.constArgumentsGround evidence.requirements
    evidence.argumentMatches.substitutes evidence.argumentGrounds
    evidence.returnSubstitute evidence.returnGrounds explicitGround

/-- Non-recursive evidence attached to one direct call whose generic arguments
    are written at the call site. The recursive specialization relation owns
    the checked argument expressions and therefore fixes their exact Core
    outputs. -/
structure DirectCallExplicitEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path : Surface.Path)
    (parameterTypes : List Static.Ty)
    (returnType : Static.Ty)
    (scheme : Static.FunctionScheme)
    (inner : Static.SymbolicSubstitution)
    (resolved : Static.FunctionInstance) : Type where
  symbolicTypeArguments : List Static.Ty
  symbolicConstArguments : List Static.Const
  groundTypeArguments : List Static.GroundTy
  groundConstArguments : List Nat
  selected : SourceWellFormed.SelectsFunction symbolic.scopeContext path scheme
  explicitArguments : ExplicitGenericArgumentsRetain symbolic.globals path
    scheme.genericParameters inner
  genericArguments : Static.SymbolicArgumentsBound inner
    scheme.genericParameters symbolicTypeArguments symbolicConstArguments
  typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
    some groundTypeArguments
  constArgumentsGround : Static.instantiateConstants outer
    symbolicConstArguments = some groundConstArguments
  parametersSubstitute : Static.substituteTypes inner scheme.parameterTypes =
    some parameterTypes
  requirements : Static.SymbolicRequirementsGround
    symbolic.globals.implementations symbolic.assumptions outer inner
    scheme.requirements
  returnSubstitute : scheme.returnType.substitute inner = some returnType
  parameterGrounds : Static.instantiateTypes outer parameterTypes =
    some resolved.parameterTypes
  returnGrounds : returnType.instantiate outer = some resolved.returnType
  artifact : FunctionArtifactDemand concrete path scheme groundTypeArguments
    groundConstArguments resolved
  notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none

theorem DirectCallExplicitEvidence.symbolicInference
    (evidence : DirectCallExplicitEvidence outer concrete symbolic path
      parameterTypes returnType scheme inner resolved)
    (arguments : SymbolicExprsCheck symbolic surfaceArguments parameterTypes) :
    SymbolicExprInfers symbolic (.call (.path path) surfaceArguments) returnType := by
  exact .directCallExplicit evidence.selected evidence.explicitArguments
    evidence.parametersSubstitute arguments evidence.requirements.symbolic
    evidence.returnSubstitute evidence.notIntrinsic

theorem DirectCallExplicitEvidence.resolvesDirectCall
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : DirectCallExplicitEvidence outer concrete symbolic path
      parameterTypes returnType scheme inner resolved) :
    SurfaceElaboration.ResolvesDirectCall concrete path resolved.parameterTypes
      scheme resolved := by
  have parametersGround := evidence.genericArguments.parametersGround
    evidence.typeArgumentsGround evidence.constArgumentsGround
  obtain ⟨head, tail, found, explicitGrounds⟩ :=
    evidence.explicitArguments.specializes contexts parametersGround
  have explicitGround : SurfaceElaboration.ExplicitCallArgumentsGround concrete
      path scheme.genericParameters (inner.composeGround outer) := by
    unfold SurfaceElaboration.ExplicitCallArgumentsGround
    rw [found]
    exact explicitGrounds
  exact evidence.artifact.resolvesDirectCall contexts evidence.selected
    evidence.genericArguments evidence.typeArgumentsGround
    evidence.constArgumentsGround evidence.requirements
    evidence.parametersSubstitute evidence.parameterGrounds
    evidence.returnSubstitute evidence.returnGrounds explicitGround

/-- Non-recursive evidence attached to one nongeneric direct call. It records
    that the selected declaration is closed and identifies the exact emitted
    function artifact; checked argument traversal remains recursive. -/
structure DirectCallNongenericEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path : Surface.Path)
    (scheme : Static.FunctionScheme)
    (resolved : Static.FunctionInstance) : Type where
  selected : SourceWellFormed.SelectsFunction symbolic.scopeContext path scheme
  implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path
  nongeneric : scheme.genericParameters = []
  requirements : Static.SymbolicRequirementsGround
    symbolic.globals.implementations symbolic.assumptions outer {}
    scheme.requirements
  parametersClosed : Static.substituteTypes {} scheme.parameterTypes =
    some scheme.parameterTypes
  returnClosed : scheme.returnType.substitute {} = some scheme.returnType
  parameterGrounds : Static.instantiateTypes outer scheme.parameterTypes =
    some resolved.parameterTypes
  returnGrounds : scheme.returnType.instantiate outer = some resolved.returnType
  artifact : FunctionArtifactDemand concrete path scheme [] [] resolved
  notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none

theorem DirectCallNongenericEvidence.symbolicInference
    (evidence : DirectCallNongenericEvidence outer concrete symbolic path
      scheme resolved)
    (arguments : SymbolicExprsCheck symbolic surfaceArguments
      scheme.parameterTypes) :
    SymbolicExprInfers symbolic (.call (.path path) surfaceArguments)
      scheme.returnType := by
  exact .directCallNongeneric evidence.selected evidence.implicitArguments
    evidence.nongeneric arguments evidence.requirements.symbolic
    evidence.notIntrinsic

theorem DirectCallNongenericEvidence.resolvesDirectCall
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : DirectCallNongenericEvidence outer concrete symbolic path
      scheme resolved) :
    SurfaceElaboration.ResolvesDirectCall concrete path resolved.parameterTypes
      scheme resolved := by
  have genericArguments : Static.SymbolicArgumentsBound {}
      scheme.genericParameters [] [] := by
    rw [evidence.nongeneric]
    exact .nil
  have explicitGround : SurfaceElaboration.ExplicitCallArgumentsGround concrete
      path scheme.genericParameters
      (({} : Static.SymbolicSubstitution).composeGround outer) := by
    unfold SurfaceElaboration.ExplicitCallArgumentsGround
    rw [evidence.implicitArguments]
    trivial
  exact evidence.artifact.resolvesDirectCall contexts evidence.selected
    genericArguments rfl rfl evidence.requirements evidence.parametersClosed
    evidence.parameterGrounds evidence.returnClosed evidence.returnGrounds
    explicitGround

/-- Non-recursive evidence for one inferred method selection and its exact
    emitted artifact. Receiver/member lowering and argument traversal remain
    children of the recursive expression derivation. -/
structure MethodCallInferenceEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (receiverType : Static.Ty)
    (name : Surface.Name)
    (observedTypes : List Static.Ty)
    (returnType : Static.Ty)
    (scheme : Static.MethodScheme)
    (inner : Static.SymbolicSubstitution)
    (resolved : Static.MethodInstance) : Type where
  symbolicTypeArguments : List Static.Ty
  symbolicConstArguments : List Static.Const
  groundTypeArguments : List Static.GroundTy
  groundConstArguments : List Nat
  schemeMember : scheme ∈ symbolic.globals.methods
  schemeName : scheme.name = name
  memberMode : scheme.receiverMode ≠ .none
  genericArguments : Static.SymbolicArgumentsBound inner
    scheme.genericParameters symbolicTypeArguments symbolicConstArguments
  typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
    some groundTypeArguments
  constArgumentsGround : Static.instantiateConstants outer
    symbolicConstArguments = some groundConstArguments
  receiverMatch : Static.TySymbolicallyMatches inner
    scheme.receiverType receiverType
  argumentMatches : Static.TypesSymbolicallyMatch inner
    scheme.argumentTypes observedTypes
  determined : SurfaceElaboration.TypesDetermineGenericParameters
    (scheme.receiverType :: scheme.argumentTypes) scheme.genericParameters
  requirements : Static.SymbolicRequirementsGround
    symbolic.globals.implementations symbolic.assumptions outer inner
    scheme.requirements
  returnSubstitute : scheme.returnType.substitute inner = some returnType
  symbolicPreferred : scheme.preferredAt symbolic.globals.methods
    symbolic.globals.currentModule
    (SymbolicMethodLookupApplicable symbolic receiverType name)
  receiverGrounds : receiverType.instantiate outer = some resolved.receiverType
  argumentGrounds : Static.instantiateTypes outer observedTypes =
    some resolved.argumentTypes
  returnGrounds : returnType.instantiate outer = some resolved.returnType
  artifact : MethodArtifactDemand concrete scheme groundTypeArguments
    groundConstArguments resolved
  groundPreferred : scheme.preferredAt concrete.methods concrete.currentModule
    (Static.GroundMethodLookupApplicable concrete.implementations
      concrete.methodInstances resolved.receiverType name)
  coherent : Static.MethodLookupCoherent concrete.implementations
    concrete.methods concrete.methodInstances
  unique : ∀ candidate,
    candidate ∈ symbolic.globals.methods →
    SymbolicMethodLookupApplicable symbolic receiverType name candidate →
    candidate.preferredAt symbolic.globals.methods symbolic.globals.currentModule
      (SymbolicMethodLookupApplicable symbolic receiverType name) →
    candidate.declaration = scheme.declaration

theorem MethodCallInferenceEvidence.selection
    (evidence : MethodCallInferenceEvidence outer concrete symbolic receiverType
      name observedTypes returnType scheme inner resolved) :
    SelectsSymbolicMethod symbolic receiverType name observedTypes returnType := by
  exact ⟨scheme, inner, evidence.schemeMember, evidence.schemeName,
    evidence.memberMode, evidence.receiverMatch, evidence.argumentMatches,
    evidence.determined,
    evidence.genericArguments.parametersBound, evidence.requirements.symbolic,
    evidence.returnSubstitute, evidence.symbolicPreferred, evidence.unique⟩

theorem MethodCallInferenceEvidence.symbolicInference
    (evidence : MethodCallInferenceEvidence outer concrete symbolic receiverType
      name observedTypes returnType scheme inner resolved)
    (receiver : SymbolicExprInfers symbolic surfaceReceiver sourceReceiver)
    (memberBase : SymbolicMemberBase sourceReceiver receiverType)
    (arguments : SymbolicExprsInfer symbolic surfaceArguments observedTypes) :
    SymbolicExprInfers symbolic
      (.call (.member surfaceReceiver name) surfaceArguments) returnType := by
  exact .methodCall receiver memberBase arguments evidence.selection

theorem MethodCallInferenceEvidence.concreteSpecialization
    {groundEnclosingReturn : Static.GroundTy}
    {sourceGround : Static.GroundTy}
    {sourceReceiver : Static.Ty}
    {sourceCore receiverCore receiverArgumentCore : Core.Expr}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : MethodCallInferenceEvidence outer concrete symbolic receiverType
      name observedTypes returnType scheme inner resolved)
    (sourceGrounds : sourceReceiver.instantiate outer = some sourceGround)
    (sourceLowers : SurfaceElaboration.ExprLowers concrete surfaceReceiver
      sourceGround sourceCore)
    (memberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      sourceGround sourceCore resolved.receiverType receiverCore)
    (arguments : ExprsInferMatchedSpecialize outer concrete symbolic inner
      surfaceArguments scheme.argumentTypes observedTypes)
    (receiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization resolved.receiverMode resolved.receiverType
      receiverCore receiverArgumentCore) :
    ExprSpecializes outer concrete
      (.call (.member surfaceReceiver name) surfaceArguments) returnType := by
  have member : MemberBaseSpecializes outer concrete surfaceReceiver sourceReceiver
      receiverType resolved.receiverType receiverCore :=
    .intro sourceGround sourceCore sourceGrounds evidence.receiverGrounds
      sourceLowers memberLowers
  exact SymbolicExprInfers.methodCallSpecializes contexts member
    evidence.schemeMember evidence.schemeName evidence.memberMode
    evidence.genericArguments
    evidence.typeArgumentsGround evidence.constArgumentsGround
    evidence.requirements evidence.receiverMatch.substitutes
    evidence.argumentMatches.substitutes arguments.checkSpecializes
    evidence.argumentGrounds evidence.returnSubstitute evidence.returnGrounds
    evidence.artifact rfl rfl rfl evidence.groundPreferred evidence.coherent
    receiverArgument

theorem MethodCallInferenceEvidence.concreteLowering
    {groundEnclosingReturn sourceGround : Static.GroundTy}
    {sourceReceiver : Static.Ty}
    {sourceCore receiverCore receiverArgumentCore : Core.Expr}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : MethodCallInferenceEvidence outer concrete symbolic receiverType
      name observedTypes returnType scheme inner resolved)
    (sourceGrounds : sourceReceiver.instantiate outer = some sourceGround)
    (sourceLowers : SurfaceElaboration.ExprLowers concrete surfaceReceiver
      sourceGround sourceCore)
    (memberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      sourceGround sourceCore resolved.receiverType receiverCore)
    (arguments : SurfaceElaboration.ExprsCheck concrete surfaceArguments
      resolved.argumentTypes coreArguments)
    (receiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization resolved.receiverMode resolved.receiverType
      receiverCore receiverArgumentCore) :
    SurfaceElaboration.ExprLowers concrete
      (.call (.member surfaceReceiver name) surfaceArguments)
      resolved.returnType
      (.call resolved.function (receiverArgumentCore :: coreArguments)) := by
  have member : MemberBaseSpecializes outer concrete surfaceReceiver sourceReceiver
      receiverType resolved.receiverType receiverCore :=
    .intro sourceGround sourceCore sourceGrounds evidence.receiverGrounds
      sourceLowers memberLowers
  have resolvedMethod := evidence.artifact.resolvesMethod contexts
    evidence.schemeMember evidence.schemeName evidence.memberMode
    evidence.genericArguments
    evidence.typeArgumentsGround evidence.constArgumentsGround
    evidence.requirements evidence.receiverMatch.substitutes
    evidence.receiverGrounds evidence.argumentMatches.substitutes
    evidence.argumentGrounds evidence.returnSubstitute evidence.returnGrounds
    rfl rfl rfl evidence.groundPreferred evidence.coherent
  have instantiated : Static.MethodInstantiates concrete.implementations scheme
      (inner.composeGround outer) resolved :=
    evidence.artifact.instantiates contexts evidence.genericArguments
      evidence.typeArgumentsGround evidence.constArgumentsGround
      evidence.requirements evidence.receiverMatch.substitutes
      evidence.receiverGrounds evidence.argumentMatches.substitutes
      evidence.argumentGrounds evidence.returnSubstitute evidence.returnGrounds
  have resolvedName : resolved.name = name :=
    instantiated.signature.2.2.2.2.1.trans evidence.schemeName
  have lowered : Elaboration.MethodCallLowers concrete.implementations
      concrete.methods concrete.methodInstances concrete.currentModule
      concrete.monomorphization receiverCore resolved.receiverType name coreArguments
      resolved.argumentTypes resolved.returnType
      (.call resolved.function (receiverArgumentCore :: coreArguments)) :=
    .call scheme resolved resolvedMethod (inner.composeGround outer) instantiated
      rfl resolvedName rfl receiverArgumentCore receiverArgument
  exact .methodCall sourceLowers memberLowers arguments lowered

structure MethodCallContextualEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (receiverType : Static.Ty)
    (name : Surface.Name)
    (expectedArgumentTypes : List Static.Ty)
    (returnType : Static.Ty)
    (scheme : Static.MethodScheme)
    (inner : Static.SymbolicSubstitution)
    (resolved : Static.MethodInstance) : Type where
  symbolicTypeArguments : List Static.Ty
  symbolicConstArguments : List Static.Const
  groundTypeArguments : List Static.GroundTy
  groundConstArguments : List Nat
  schemeMember : scheme ∈ symbolic.globals.methods
  schemeName : scheme.name = name
  memberMode : scheme.receiverMode ≠ .none
  genericArguments : Static.SymbolicArgumentsBound inner
    scheme.genericParameters symbolicTypeArguments symbolicConstArguments
  typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
    some groundTypeArguments
  constArgumentsGround : Static.instantiateConstants outer
    symbolicConstArguments = some groundConstArguments
  receiverMatch : Static.TySymbolicallyMatches inner
    scheme.receiverType receiverType
  symbolicPreferred : scheme.preferredAt symbolic.globals.methods
    symbolic.globals.currentModule
    (SymbolicMethodLookupApplicable symbolic receiverType name)
  determined : SurfaceElaboration.TypesDetermineGenericParameters
    [scheme.receiverType] scheme.genericParameters
  requirements : Static.SymbolicRequirementsGround
    symbolic.globals.implementations symbolic.assumptions outer inner
    scheme.requirements
  argumentsSubstitute : Static.substituteTypes inner scheme.argumentTypes =
    some expectedArgumentTypes
  returnSubstitute : scheme.returnType.substitute inner = some returnType
  receiverGrounds : receiverType.instantiate outer = some resolved.receiverType
  argumentGrounds : Static.instantiateTypes outer expectedArgumentTypes =
    some resolved.argumentTypes
  returnGrounds : returnType.instantiate outer = some resolved.returnType
  artifact : MethodArtifactDemand concrete scheme groundTypeArguments
    groundConstArguments resolved
  groundPreferred : scheme.preferredAt concrete.methods concrete.currentModule
    (Static.GroundMethodLookupApplicable concrete.implementations
      concrete.methodInstances resolved.receiverType name)
  coherent : Static.MethodLookupCoherent concrete.implementations
    concrete.methods concrete.methodInstances
  unique : ∀ candidate,
    candidate ∈ symbolic.globals.methods →
    SymbolicMethodLookupApplicable symbolic receiverType name candidate →
    candidate.preferredAt symbolic.globals.methods symbolic.globals.currentModule
      (SymbolicMethodLookupApplicable symbolic receiverType name) →
    candidate.declaration = scheme.declaration

theorem MethodCallContextualEvidence.selection
    (evidence : MethodCallContextualEvidence outer concrete symbolic receiverType
      name expectedArgumentTypes returnType scheme inner resolved) :
    SelectsContextualSymbolicMethod symbolic receiverType name scheme inner
      expectedArgumentTypes returnType := by
  exact ⟨⟨evidence.schemeMember, evidence.schemeName, evidence.memberMode,
    evidence.receiverMatch, evidence.genericArguments.parametersBound,
    evidence.requirements.symbolic,
    evidence.argumentsSubstitute, evidence.returnSubstitute⟩,
    evidence.symbolicPreferred, evidence.determined, evidence.unique⟩

theorem MethodCallContextualEvidence.symbolicInference
    (evidence : MethodCallContextualEvidence outer concrete symbolic receiverType
      name expectedArgumentTypes returnType scheme inner resolved)
    (receiver : SymbolicExprInfers symbolic surfaceReceiver sourceReceiver)
    (memberBase : SymbolicMemberBase sourceReceiver receiverType)
    (arguments : SymbolicExprsCheck symbolic surfaceArguments
      expectedArgumentTypes) :
    SymbolicExprInfers symbolic
      (.call (.member surfaceReceiver name) surfaceArguments) returnType := by
  exact .methodCallContextual receiver memberBase evidence.selection arguments

theorem MethodCallContextualEvidence.concreteLowering
    {groundEnclosingReturn sourceGround : Static.GroundTy}
    {sourceCore receiverCore receiverArgumentCore : Core.Expr}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : MethodCallContextualEvidence outer concrete symbolic receiverType
      name expectedArgumentTypes returnType scheme inner resolved)
    (sourceLowers : SurfaceElaboration.ExprLowers concrete surfaceReceiver
      sourceGround sourceCore)
    (memberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      sourceGround sourceCore resolved.receiverType receiverCore)
    (arguments : SurfaceElaboration.ExprsCheck concrete surfaceArguments
      resolved.argumentTypes coreArguments)
    (receiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization resolved.receiverMode resolved.receiverType
      receiverCore receiverArgumentCore) :
    SurfaceElaboration.ExprLowers concrete
      (.call (.member surfaceReceiver name) surfaceArguments)
      resolved.returnType
      (.call resolved.function (receiverArgumentCore :: coreArguments)) := by
  have resolvedMethod := evidence.artifact.resolvesMethod contexts
    evidence.schemeMember evidence.schemeName evidence.memberMode
    evidence.genericArguments
    evidence.typeArgumentsGround evidence.constArgumentsGround
    evidence.requirements evidence.receiverMatch.substitutes
    evidence.receiverGrounds evidence.argumentsSubstitute evidence.argumentGrounds
    evidence.returnSubstitute evidence.returnGrounds rfl rfl rfl
    evidence.groundPreferred evidence.coherent
  have instantiated : Static.MethodInstantiates concrete.implementations scheme
      (inner.composeGround outer) resolved :=
    evidence.artifact.instantiates contexts evidence.genericArguments
      evidence.typeArgumentsGround evidence.constArgumentsGround
      evidence.requirements evidence.receiverMatch.substitutes
      evidence.receiverGrounds evidence.argumentsSubstitute evidence.argumentGrounds
      evidence.returnSubstitute evidence.returnGrounds
  have resolvedName : resolved.name = name :=
    instantiated.signature.2.2.2.2.1.trans evidence.schemeName
  have lowered : Elaboration.MethodCallLowers concrete.implementations
      concrete.methods concrete.methodInstances concrete.currentModule
      concrete.monomorphization receiverCore resolved.receiverType name coreArguments
      resolved.argumentTypes resolved.returnType
      (.call resolved.function (receiverArgumentCore :: coreArguments)) :=
    .call scheme resolved resolvedMethod (inner.composeGround outer) instantiated
      rfl resolvedName rfl receiverArgumentCore receiverArgument
  exact .methodCall sourceLowers memberLowers arguments lowered

/-- Complete evidence for an associated inherent-function call whose ordinary
    arguments are inferred before matching the selected source signature. -/
structure AssociatedCallInferenceEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path ownerPath : Surface.Path)
    (name : Surface.Name)
    (receiverType : Static.Ty)
    (sourceParameterTypes observedTypes : List Static.Ty)
    (groundArgumentTypes : List Static.GroundTy)
    (returnType : Static.Ty)
    (scheme : Static.MethodScheme)
    (inner : Static.SymbolicSubstitution)
    (resolved : Static.MethodInstance) : Type where
  symbolicTypeArguments : List Static.Ty
  symbolicConstArguments : List Static.Const
  groundTypeArguments : List Static.GroundTy
  groundConstArguments : List Nat
  symbolicStoredArguments : List Static.Ty
  split : SurfaceElaboration.associatedFunctionPath? path = some (ownerPath, name)
  notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none
  notFunction : ¬ ∃ candidate,
    SourceWellFormed.SelectsFunction symbolic.scopeContext path candidate
  notVariant : ¬ ∃ constructor,
    SelectsSymbolicVariantConstructor symbolic path constructor
  owner : TypeRetains symbolic.globals (.path ownerPath.segments) receiverType
  schemeMember : scheme ∈ symbolic.globals.methods
  schemeName : scheme.name = name
  associatedParameters : scheme.associatedArgumentTypes? =
    some sourceParameterTypes
  genericArguments : Static.SymbolicArgumentsBound inner
    scheme.genericParameters symbolicTypeArguments symbolicConstArguments
  typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
    some groundTypeArguments
  constArgumentsGround : Static.instantiateConstants outer
    symbolicConstArguments = some groundConstArguments
  receiverMatch : Static.TySymbolicallyMatches inner
    scheme.receiverType receiverType
  argumentMatches : Static.TypesSymbolicallyMatch inner
    sourceParameterTypes observedTypes
  determined : SurfaceElaboration.TypesDetermineGenericParameters
    (scheme.receiverType :: scheme.argumentTypes) scheme.genericParameters
  requirements : Static.SymbolicRequirementsGround
    symbolic.globals.implementations symbolic.assumptions outer inner
    scheme.requirements
  returnSubstitute : scheme.returnType.substitute inner = some returnType
  symbolicPreferred : scheme.preferredAt symbolic.globals.methods
    symbolic.globals.currentModule
    (SymbolicMethodLookupApplicable symbolic receiverType name)
  ownerGrounds : receiverType.instantiate outer = some resolved.receiverType
  argumentGrounds : Static.instantiateTypes outer observedTypes =
    some groundArgumentTypes
  storedArgumentsSubstitute : Static.substituteTypes inner scheme.argumentTypes =
    some symbolicStoredArguments
  storedArgumentsGround : Static.instantiateTypes outer symbolicStoredArguments =
    some resolved.argumentTypes
  resolvedAssociatedArguments : resolved.associatedArgumentTypes? =
    some groundArgumentTypes
  returnGrounds : returnType.instantiate outer = some resolved.returnType
  artifact : MethodArtifactDemand concrete scheme groundTypeArguments
    groundConstArguments resolved
  groundPreferred : scheme.preferredAt concrete.methods concrete.currentModule
    (Static.GroundMethodLookupApplicable concrete.implementations
      concrete.methodInstances resolved.receiverType name)
  coherent : Static.MethodLookupCoherent concrete.implementations
    concrete.methods concrete.methodInstances
  unique : ∀ candidate,
    candidate ∈ symbolic.globals.methods →
    SymbolicMethodLookupApplicable symbolic receiverType name candidate →
    candidate.preferredAt symbolic.globals.methods symbolic.globals.currentModule
      (SymbolicMethodLookupApplicable symbolic receiverType name) →
    candidate.declaration = scheme.declaration

theorem AssociatedCallInferenceEvidence.selection
    (evidence : AssociatedCallInferenceEvidence outer concrete symbolic path
      ownerPath name receiverType sourceParameterTypes observedTypes
      groundArgumentTypes returnType scheme inner resolved) :
    SelectsSymbolicAssociatedMethod symbolic receiverType name observedTypes
      returnType := by
  exact ⟨scheme, inner, sourceParameterTypes, evidence.schemeMember,
    evidence.schemeName, evidence.associatedParameters, evidence.receiverMatch,
    evidence.argumentMatches, evidence.determined,
    evidence.genericArguments.parametersBound, evidence.requirements.symbolic,
    evidence.returnSubstitute, evidence.symbolicPreferred, evidence.unique⟩

theorem AssociatedCallInferenceEvidence.symbolicInference
    (evidence : AssociatedCallInferenceEvidence outer concrete symbolic path
      ownerPath name receiverType sourceParameterTypes observedTypes
      groundArgumentTypes returnType scheme inner resolved)
    (arguments : SymbolicExprsInfer symbolic surfaceArguments observedTypes) :
    SymbolicExprInfers symbolic (.call (.path path) surfaceArguments)
      returnType :=
  .associatedCall evidence.split evidence.notIntrinsic evidence.notFunction
    evidence.notVariant evidence.owner arguments evidence.selection

theorem AssociatedCallInferenceEvidence.resolution
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : AssociatedCallInferenceEvidence outer concrete symbolic path
      ownerPath name receiverType sourceParameterTypes observedTypes
      groundArgumentTypes returnType scheme inner resolved) :
    Static.ResolvesAssociatedMethod concrete.implementations concrete.methods
      concrete.methodInstances concrete.currentModule resolved.receiverType name
      groundArgumentTypes scheme resolved := by
  exact evidence.artifact.resolvesAssociatedMethod contexts evidence.schemeMember
    evidence.schemeName evidence.genericArguments evidence.typeArgumentsGround
    evidence.constArgumentsGround evidence.requirements
    evidence.receiverMatch.substitutes evidence.ownerGrounds
    evidence.storedArgumentsSubstitute evidence.storedArgumentsGround
    evidence.returnSubstitute evidence.returnGrounds rfl
    evidence.resolvedAssociatedArguments evidence.groundPreferred evidence.coherent

theorem AssociatedCallInferenceEvidence.concreteLowering
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : AssociatedCallInferenceEvidence outer concrete symbolic path
      ownerPath name receiverType sourceParameterTypes observedTypes
      groundArgumentTypes returnType scheme inner resolved)
    (arguments : SurfaceElaboration.ExprsCheck concrete surfaceArguments
      groundArgumentTypes coreArguments) :
    SurfaceElaboration.ExprLowers concrete
      (.call (.path path) surfaceArguments) resolved.returnType
      (.call resolved.function coreArguments) := by
  have lowered : Elaboration.AssociatedCallLowers concrete.implementations
      concrete.methods concrete.methodInstances concrete.currentModule
      resolved.receiverType name coreArguments groundArgumentTypes
      resolved.returnType (.call resolved.function coreArguments) :=
    .call scheme resolved (evidence.resolution contexts)
  exact .associatedCall evidence.split
    (evidence.owner.specializes contexts evidence.ownerGrounds) arguments lowered

/-- Contextual associated-call evidence checks literals and other context-only
    expressions after the owner type has fixed the inherent declaration. -/
structure AssociatedCallContextualEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path ownerPath : Surface.Path)
    (name : Surface.Name)
    (receiverType : Static.Ty)
    (sourceParameterTypes expectedArgumentTypes : List Static.Ty)
    (groundArgumentTypes : List Static.GroundTy)
    (returnType : Static.Ty)
    (scheme : Static.MethodScheme)
    (inner : Static.SymbolicSubstitution)
    (resolved : Static.MethodInstance) : Type where
  symbolicTypeArguments : List Static.Ty
  symbolicConstArguments : List Static.Const
  groundTypeArguments : List Static.GroundTy
  groundConstArguments : List Nat
  symbolicStoredArguments : List Static.Ty
  split : SurfaceElaboration.associatedFunctionPath? path = some (ownerPath, name)
  notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none
  notFunction : ¬ ∃ candidate,
    SourceWellFormed.SelectsFunction symbolic.scopeContext path candidate
  notVariant : ¬ ∃ constructor,
    SelectsSymbolicVariantConstructor symbolic path constructor
  owner : TypeRetains symbolic.globals (.path ownerPath.segments) receiverType
  schemeMember : scheme ∈ symbolic.globals.methods
  schemeName : scheme.name = name
  associatedParameters : scheme.associatedArgumentTypes? =
    some sourceParameterTypes
  genericArguments : Static.SymbolicArgumentsBound inner
    scheme.genericParameters symbolicTypeArguments symbolicConstArguments
  typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
    some groundTypeArguments
  constArgumentsGround : Static.instantiateConstants outer
    symbolicConstArguments = some groundConstArguments
  receiverMatch : Static.TySymbolicallyMatches inner
    scheme.receiverType receiverType
  determined : SurfaceElaboration.TypesDetermineGenericParameters
    [scheme.receiverType] scheme.genericParameters
  requirements : Static.SymbolicRequirementsGround
    symbolic.globals.implementations symbolic.assumptions outer inner
    scheme.requirements
  argumentsSubstitute : Static.substituteTypes inner sourceParameterTypes =
    some expectedArgumentTypes
  returnSubstitute : scheme.returnType.substitute inner = some returnType
  symbolicPreferred : scheme.preferredAt symbolic.globals.methods
    symbolic.globals.currentModule
    (SymbolicMethodLookupApplicable symbolic receiverType name)
  ownerGrounds : receiverType.instantiate outer = some resolved.receiverType
  argumentGrounds : Static.instantiateTypes outer expectedArgumentTypes =
    some groundArgumentTypes
  storedArgumentsSubstitute : Static.substituteTypes inner scheme.argumentTypes =
    some symbolicStoredArguments
  storedArgumentsGround : Static.instantiateTypes outer symbolicStoredArguments =
    some resolved.argumentTypes
  resolvedAssociatedArguments : resolved.associatedArgumentTypes? =
    some groundArgumentTypes
  returnGrounds : returnType.instantiate outer = some resolved.returnType
  artifact : MethodArtifactDemand concrete scheme groundTypeArguments
    groundConstArguments resolved
  groundPreferred : scheme.preferredAt concrete.methods concrete.currentModule
    (Static.GroundMethodLookupApplicable concrete.implementations
      concrete.methodInstances resolved.receiverType name)
  coherent : Static.MethodLookupCoherent concrete.implementations
    concrete.methods concrete.methodInstances
  unique : ∀ candidate,
    candidate ∈ symbolic.globals.methods →
    SymbolicMethodLookupApplicable symbolic receiverType name candidate →
    candidate.preferredAt symbolic.globals.methods symbolic.globals.currentModule
      (SymbolicMethodLookupApplicable symbolic receiverType name) →
    candidate.declaration = scheme.declaration

theorem AssociatedCallContextualEvidence.selection
    (evidence : AssociatedCallContextualEvidence outer concrete symbolic path
      ownerPath name receiverType sourceParameterTypes expectedArgumentTypes
      groundArgumentTypes returnType scheme inner resolved) :
    SelectsContextualSymbolicAssociatedMethod symbolic receiverType name scheme
      inner expectedArgumentTypes returnType := by
  exact ⟨sourceParameterTypes, evidence.schemeMember, evidence.schemeName,
    evidence.associatedParameters, evidence.receiverMatch,
    evidence.genericArguments.parametersBound, evidence.requirements.symbolic,
    evidence.argumentsSubstitute, evidence.returnSubstitute,
    evidence.symbolicPreferred, evidence.determined, evidence.unique⟩

theorem AssociatedCallContextualEvidence.symbolicInference
    (evidence : AssociatedCallContextualEvidence outer concrete symbolic path
      ownerPath name receiverType sourceParameterTypes expectedArgumentTypes
      groundArgumentTypes returnType scheme inner resolved)
    (arguments : SymbolicExprsCheck symbolic surfaceArguments
      expectedArgumentTypes) :
    SymbolicExprInfers symbolic (.call (.path path) surfaceArguments)
      returnType :=
  .associatedCallContextual evidence.split evidence.notIntrinsic
    evidence.notFunction evidence.notVariant evidence.owner evidence.selection
    arguments

theorem AssociatedCallContextualEvidence.resolution
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : AssociatedCallContextualEvidence outer concrete symbolic path
      ownerPath name receiverType sourceParameterTypes expectedArgumentTypes
      groundArgumentTypes returnType scheme inner resolved) :
    Static.ResolvesAssociatedMethod concrete.implementations concrete.methods
      concrete.methodInstances concrete.currentModule resolved.receiverType name
      groundArgumentTypes scheme resolved := by
  exact evidence.artifact.resolvesAssociatedMethod contexts evidence.schemeMember
    evidence.schemeName evidence.genericArguments evidence.typeArgumentsGround
    evidence.constArgumentsGround evidence.requirements
    evidence.receiverMatch.substitutes evidence.ownerGrounds
    evidence.storedArgumentsSubstitute evidence.storedArgumentsGround
    evidence.returnSubstitute evidence.returnGrounds rfl
    evidence.resolvedAssociatedArguments evidence.groundPreferred evidence.coherent

theorem AssociatedCallContextualEvidence.concreteLowering
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : AssociatedCallContextualEvidence outer concrete symbolic path
      ownerPath name receiverType sourceParameterTypes expectedArgumentTypes
      groundArgumentTypes returnType scheme inner resolved)
    (arguments : SurfaceElaboration.ExprsCheck concrete surfaceArguments
      groundArgumentTypes coreArguments) :
    SurfaceElaboration.ExprLowers concrete
      (.call (.path path) surfaceArguments) resolved.returnType
      (.call resolved.function coreArguments) := by
  have lowered : Elaboration.AssociatedCallLowers concrete.implementations
      concrete.methods concrete.methodInstances concrete.currentModule
      resolved.receiverType name coreArguments groundArgumentTypes
      resolved.returnType (.call resolved.function coreArguments) :=
    .call scheme resolved (evidence.resolution contexts)
  exact .associatedCall evidence.split
    (evidence.owner.specializes contexts evidence.ownerGrounds) arguments lowered

/- One recursive pattern derivation owns symbolic selection, grounding,
    concrete artifact selection, local-ID allocation, and the emitted Core
    pattern. Nested enum payloads cannot pair an unrelated symbolic constructor
    proof with a separately chosen concrete lowering. -/
mutual
  inductive PatternDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        VarId → Surface.Pattern → Static.Ty → Static.GroundTy →
        Core.Pattern → List SymbolicLocalBinding →
        List SurfaceElaboration.LocalBinding → VarId → Prop where
    | wildcard
        (typeGrounds : symbolicType.instantiate outer = some groundType) :
        PatternDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts next .wildcard symbolicType
          groundType .wildcard [] [] next
    | bind
        (single : SurfaceElaboration.singleNamePath? path = some name)
        (notVariant : SurfaceElaboration.NoGlobalValueResolution
          symbolic.globals path)
        (typeGrounds : symbolicType.instantiate outer = some groundType)
        (bounded : SurfaceElaboration.LocalIdsBelow concrete next) :
        PatternDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts next (.path path []) symbolicType groundType (.bind next)
          [{ name, type := symbolicType }]
          [{ name, id := next, type := groundType }] (next + 1)
    | integer
        (lowered : Elaboration.LiteralElaborates symbolic.globals.target
          (.integer text) (.scalar scalar) (.value value)) :
        PatternDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts next (.integer text) (.scalar scalar) (.scalar scalar)
          (.literal value) [] [] next
    | boolean :
        PatternDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts next (.boolean value) (.scalar .bool) (.scalar .bool)
          (.literal (.boolean value)) [] [] next
    | variant
        (receiver : symbolicType = .nominal constructor.sourceType
          symbolicTypeArguments symbolicConstArguments)
        (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
        (arguments : Static.SymbolicArgumentsBound inner
          constructor.genericParameters symbolicTypeArguments
          symbolicConstArguments)
        (typeArgumentsGround : Static.instantiateTypes outer
          symbolicTypeArguments = some groundTypeArguments)
        (constArgumentsGround : Static.instantiateConstants outer
          symbolicConstArguments = some groundConstArguments)
        (payloadSubstitute : Static.substituteTypes inner constructor.payload =
          some expectedPayload)
        (payload : PatternListDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts next surfacePayload expectedPayload
          groundPayload corePayload symbolicBindings concreteBindings final)
        (artifact : VariantArtifactDemand concrete constructor
          (.nominal constructor.sourceType groundTypeArguments
            groundConstArguments) groundPayload entry)
        (bounded : SurfaceElaboration.LocalIdsBelow concrete next) :
        PatternDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts next (.path path surfacePayload) symbolicType
          (.nominal constructor.sourceType groundTypeArguments
            groundConstArguments)
          (.enumVariant entry.coreType entry.variant corePayload)
          symbolicBindings concreteBindings final

  inductive PatternListDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        VarId → List Surface.Pattern → List Static.Ty →
        List Static.GroundTy → List Core.Pattern →
        List SymbolicLocalBinding →
        List SurfaceElaboration.LocalBinding → VarId → Prop where
    | nil : PatternListDerivationSpecializes outer groundEnclosingReturn symbolic
        concrete contexts next [] [] [] [] [] [] next
    | cons
        (head : PatternDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts next surfaceHead symbolicHead groundHead coreHead
          symbolicHeadBindings concreteHeadBindings middle)
        (tail : PatternListDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts middle surfaceTail symbolicTail groundTail
          coreTail symbolicTailBindings concreteTailBindings final)
        (distinct :
          ((symbolicHeadBindings ++ symbolicTailBindings).map (·.name)).Pairwise
            (· ≠ ·)) :
        PatternListDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts next (surfaceHead :: surfaceTail)
          (symbolicHead :: symbolicTail) (groundHead :: groundTail)
          (coreHead :: coreTail) (symbolicHeadBindings ++ symbolicTailBindings)
          (concreteHeadBindings ++ concreteTailBindings) final
end

theorem PatternDerivationSpecializes.typeGrounds
    (specialized : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundType core
      symbolicBindings concreteBindings final) :
    symbolicType.instantiate outer = some groundType := by
  cases specialized with
  | wildcard typeGrounds => exact typeGrounds
  | bind single notVariant typeGrounds bounded => exact typeGrounds
  | integer lowered => rfl
  | boolean => rfl
  | variant receiver selected arguments typeArgumentsGround constArgumentsGround
      payloadSubstitute payload artifact bounded =>
      rw [receiver]
      simp [Static.Ty.instantiate, typeArgumentsGround, constArgumentsGround]

/-- A source pattern's symbolic type and the enclosing substitution determine
    its ground type. Exact pattern specialization cannot choose a second
    monomorphic type for the same occurrence. -/
theorem PatternDerivationSpecializes.groundType_unique
    (left : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundTypeLeft
      coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft)
    (right : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundTypeRight
      coreRight symbolicBindingsRight concreteBindingsRight finalRight) :
    groundTypeLeft = groundTypeRight := by
  exact Option.some.inj (left.typeGrounds.symm.trans right.typeGrounds)

theorem PatternListDerivationSpecializes.namesDistinct
    (specialized : PatternListDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surfaces symbolicTypes groundTypes cores
      symbolicBindings concreteBindings final) :
    (symbolicBindings.map (·.name)).Pairwise (· ≠ ·) := by
  cases specialized with
  | nil => exact .nil
  | cons head tail distinct => exact distinct

private theorem exactSymbolicPatternInteger
    (lowered : Elaboration.LiteralElaborates symbolic.globals.target
      (.integer text) (.scalar scalar) (.value value)) :
    SymbolicPatternChecks symbolic (.scalar scalar) (.integer text) [] :=
  .integer ⟨scalar, .value value, rfl, lowered⟩

private theorem exactSymbolicVariantPattern
    {symbolic : SymbolicBodyContext} {outer : Static.Substitution}
    {groundReturn : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    {contexts : symbolic.Specializes outer groundReturn concrete}
    (receiver : symbolicType = .nominal constructor.sourceType
      symbolicTypeArguments symbolicConstArguments)
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
    (arguments : Static.SymbolicArgumentsBound inner
      constructor.genericParameters symbolicTypeArguments
      symbolicConstArguments)
    (payloadSubstitute : Static.substituteTypes inner constructor.payload =
      some expectedPayload)
    (payload : PatternListDerivationSpecializes outer groundReturn symbolic
      concrete contexts next surfacePayload expectedPayload groundPayload
      corePayload symbolicBindings concreteBindings final)
    (payloadSymbolic : SymbolicPatternsCheck symbolic expectedPayload
      surfacePayload symbolicBindings) :
    SymbolicPatternChecks symbolic symbolicType (.path path surfacePayload)
      symbolicBindings :=
  .variant receiver selected arguments payloadSubstitute payloadSymbolic
    payload.namesDistinct

local macro "deriveExactPatternSymbolic" outerSubstitution:ident
    groundReturn:ident recursor:term : tactic =>
  `(tactic|
    (apply $recursor
        (outer := $outerSubstitution) (groundEnclosingReturn := $groundReturn)
        (motive_1 := fun symbolic _ _ _ surface symbolicType _ _
            symbolicBindings _ _ _ =>
          SymbolicPatternChecks symbolic symbolicType surface symbolicBindings)
        (motive_2 := fun symbolic _ _ _ surfaces symbolicTypes _ _
            symbolicBindings _ _ _ =>
          SymbolicPatternsCheck symbolic symbolicTypes surfaces symbolicBindings) <;>
      intros <;>
      solve_by_elim (maxDepth := 8) [
        SymbolicPatternChecks.wildcard,
        SymbolicPatternChecks.bind,
        exactSymbolicPatternInteger,
        SymbolicPatternChecks.boolean,
        exactSymbolicVariantPattern,
        SymbolicPatternsCheck.nil,
        SymbolicPatternsCheck.cons,
        PatternListDerivationSpecializes.namesDistinct]))

theorem PatternDerivationSpecializes.symbolicPattern
    (specialized : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundType core
      symbolicBindings concreteBindings final) :
    SymbolicPatternChecks symbolic symbolicType surface symbolicBindings := by
  deriveExactPatternSymbolic outer groundEnclosingReturn
    PatternDerivationSpecializes.rec

theorem PatternListDerivationSpecializes.symbolicPatterns
    (specialized : PatternListDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surfaces symbolicTypes groundTypes cores
      symbolicBindings concreteBindings final) :
    SymbolicPatternsCheck symbolic symbolicTypes surfaces symbolicBindings := by
  deriveExactPatternSymbolic outer groundEnclosingReturn
    PatternListDerivationSpecializes.rec

local macro "deriveExactPatternAllocation" outerSubstitution:ident
    groundReturn:ident recursor:term : tactic =>
  `(tactic|
    (apply $recursor
        (outer := $outerSubstitution) (groundEnclosingReturn := $groundReturn)
        (motive_1 := fun _ _ _ next _ _ _ _ symbolicBindings
            concreteBindings final _ =>
          SymbolicBindingsAllocate $outerSubstitution next symbolicBindings
            concreteBindings final)
        (motive_2 := fun _ _ _ next _ _ _ _ symbolicBindings
            concreteBindings final _ =>
          SymbolicBindingsAllocate $outerSubstitution next symbolicBindings
            concreteBindings final) <;>
      intros <;>
      solve_by_elim (maxDepth := 8) [
        SymbolicBindingsAllocate.nil,
        SymbolicBindingsAllocate.cons,
        SymbolicBindingsAllocate.append]))

theorem PatternDerivationSpecializes.allocation
    (specialized : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundType core
      symbolicBindings concreteBindings final) :
    SymbolicBindingsAllocate outer next symbolicBindings concreteBindings
      final := by
  deriveExactPatternAllocation outer groundEnclosingReturn
    PatternDerivationSpecializes.rec

theorem PatternListDerivationSpecializes.allocation
    (specialized : PatternListDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surfaces symbolicTypes groundTypes cores
      symbolicBindings concreteBindings final) :
    SymbolicBindingsAllocate outer next symbolicBindings concreteBindings
      final := by
  deriveExactPatternAllocation outer groundEnclosingReturn
    PatternListDerivationSpecializes.rec

/-- Once symbolic pattern bindings are fixed, dense local allocation fixes
    both the concrete binding rows and the outgoing ID supply. -/
theorem PatternDerivationSpecializes.allocation_unique
    (left : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicTypeLeft groundTypeLeft
      coreLeft symbolicBindings concreteBindingsLeft finalLeft)
    (right : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicTypeRight groundTypeRight
      coreRight symbolicBindings concreteBindingsRight finalRight) :
    concreteBindingsLeft = concreteBindingsRight ∧ finalLeft = finalRight :=
  left.allocation.unique right.allocation

/-- Pattern lists use the same dense allocator, so their concrete binding rows
    and final supply are functional in the accumulated symbolic bindings too. -/
theorem PatternListDerivationSpecializes.allocation_unique
    (left : PatternListDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surfaces symbolicTypesLeft groundTypesLeft
      coresLeft symbolicBindings concreteBindingsLeft finalLeft)
    (right : PatternListDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surfaces symbolicTypesRight groundTypesRight
      coresRight symbolicBindings concreteBindingsRight finalRight) :
    concreteBindingsLeft = concreteBindingsRight ∧ finalLeft = finalRight :=
  left.allocation.unique right.allocation

private theorem exactConcretePatternInteger
    {symbolic : SymbolicBodyContext} {outer : Static.Substitution}
    {groundReturn : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (lowered : Elaboration.LiteralElaborates symbolic.globals.target
      (.integer text) (.scalar scalar) (.value value)) :
    SurfaceElaboration.PatternLowers concrete (.scalar scalar) (.integer text)
      (.literal value) [] := by
  have concreteLowered : Elaboration.LiteralElaborates concrete.target
      (.integer text) (.scalar scalar) (.value value) := by
    rw [contexts.globals]
    exact lowered
  exact .integer rfl concreteLowered

private theorem exactConcreteVariantPattern
    {symbolic : SymbolicBodyContext} {outer : Static.Substitution}
    {groundReturn : Static.GroundTy}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
    (payloadDerivation : PatternListDerivationSpecializes outer groundReturn
      symbolic concrete contexts next surfacePayload expectedPayload groundPayload
      corePayload symbolicBindings concreteBindings final)
    (payload : SurfaceElaboration.PatternsLower concrete groundPayload
      surfacePayload corePayload concreteBindings)
    (artifact : VariantArtifactDemand concrete constructor groundReceiver
      groundPayload entry)
    (bounded : SurfaceElaboration.LocalIdsBelow concrete next) :
    SurfaceElaboration.PatternLowers concrete groundReceiver
      (.path path surfacePayload)
      (.enumVariant entry.coreType entry.variant corePayload)
      concreteBindings := by
  have concretePayload : SurfaceElaboration.PatternsLower concrete entry.payload
      surfacePayload corePayload concreteBindings := by
    rw [artifact.payload]
    exact payload
  exact .variant (artifact.selectsVariant contexts selected) concretePayload
    (payloadDerivation.allocation.patternBindingsFresh bounded
      payloadDerivation.namesDistinct)

local macro "deriveExactPatternConcrete" outerSubstitution:ident
    groundReturn:ident recursor:term : tactic =>
  `(tactic|
    (apply $recursor
        (outer := $outerSubstitution) (groundEnclosingReturn := $groundReturn)
        (motive_1 := fun _ concrete _ _ surface _ groundType core _
            concreteBindings _ _ =>
          SurfaceElaboration.PatternLowers concrete groundType surface core
            concreteBindings)
        (motive_2 := fun _ concrete _ _ surfaces _ groundTypes cores _
            concreteBindings _ _ =>
          SurfaceElaboration.PatternsLower concrete groundTypes surfaces cores
            concreteBindings) <;>
      intros <;>
      solve_by_elim (maxDepth := 10) [
        SurfaceElaboration.PatternLowers.wildcard,
        SurfaceElaboration.PatternLowers.bind,
        exactConcretePatternInteger,
        SurfaceElaboration.PatternLowers.boolean,
        exactConcreteVariantPattern,
        SurfaceElaboration.PatternsLower.nil,
        SurfaceElaboration.PatternsLower.cons,
        SymbolicBodyContext.Specializes.noGlobalValueResolution,
        SurfaceElaboration.LocalIdsBelow.fresh,
        PatternDerivationSpecializes.allocation,
        PatternListDerivationSpecializes.allocation,
        PatternListDerivationSpecializes.namesDistinct]))

theorem PatternDerivationSpecializes.concretePattern
    (specialized : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundType core
      symbolicBindings concreteBindings final) :
    SurfaceElaboration.PatternLowers concrete groundType surface core
      concreteBindings := by
  deriveExactPatternConcrete outer groundEnclosingReturn
    PatternDerivationSpecializes.rec

theorem PatternListDerivationSpecializes.concretePatterns
    (specialized : PatternListDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surfaces symbolicTypes groundTypes cores
      symbolicBindings concreteBindings final) :
    SurfaceElaboration.PatternsLower concrete groundTypes surfaces cores
      concreteBindings := by
  deriveExactPatternConcrete outer groundEnclosingReturn
    PatternListDerivationSpecializes.rec

theorem PatternDerivationSpecializes.bindingsSpecialize
    (specialized : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundType core
      symbolicBindings concreteBindings final) :
    SymbolicBindingsSpecialize outer symbolicBindings concreteBindings :=
  specialized.allocation.specializes

theorem PatternDerivationSpecializes.boundContexts
    (specialized : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundType core
      symbolicBindings concreteBindings final) :
    (symbolic.bindMany symbolicBindings).Specializes outer groundEnclosingReturn
      (concrete.bindLocals concreteBindings) :=
  contexts.bindMany specialized.bindingsSpecialize

/-- The common, non-recursive provenance of one nominal construction.  A
    source-level symbolic substitution, its ordered arguments, and the emitted
    monomorphic row are recorded together so exact expression derivations
    cannot accidentally combine the fields of one constructor occurrence with
    the artifact of another. -/
structure NominalInstantiationEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (parameters : List Static.GenericParameter)
    (requirementPatterns : List Static.TraitPattern)
    (declaration : Nat)
    (sourceType : TypeId)
    (kind : Static.NominalKind)
    (inner : Static.SymbolicSubstitution)
    (symbolicTypeArguments : List Static.Ty)
    (symbolicConstArguments : List Static.Const)
    (resolved : Static.NominalInstance) : Type where
  groundTypeArguments : List Static.GroundTy
  groundConstArguments : List Nat
  arguments : Static.SymbolicArgumentsBound inner parameters
    symbolicTypeArguments symbolicConstArguments
  typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
    some groundTypeArguments
  constArgumentsGround : Static.instantiateConstants outer
    symbolicConstArguments = some groundConstArguments
  requirements : Static.SymbolicRequirementsGround
    symbolic.globals.implementations symbolic.assumptions outer inner
    requirementPatterns
  artifact : NominalArtifactDemand concrete declaration sourceType kind
    groundTypeArguments groundConstArguments resolved

theorem NominalInstantiationEvidence.typeGrounds
    (evidence : NominalInstantiationEvidence outer concrete symbolic parameters
      requirementPatterns declaration sourceType kind inner
      symbolicTypeArguments symbolicConstArguments resolved) :
    (Static.Ty.nominal sourceType symbolicTypeArguments
      symbolicConstArguments).instantiate outer =
      some (.nominal sourceType resolved.typeArguments
        resolved.constArguments) := by
  simp [Static.Ty.instantiate, evidence.typeArgumentsGround,
    evidence.constArgumentsGround, evidence.artifact.typeArguments,
    evidence.artifact.constArguments]

theorem NominalInstantiationEvidence.instantiates
    {groundEnclosingReturn : Static.GroundTy}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (evidence : NominalInstantiationEvidence outer concrete symbolic parameters
      requirementPatterns declaration sourceType kind inner
      symbolicTypeArguments symbolicConstArguments resolved) :
    SurfaceElaboration.NominalConstructorInstantiates concrete declaration
      sourceType kind parameters requirementPatterns
      (inner.composeGround outer) resolved :=
  evidence.artifact.instantiates contexts evidence.arguments
    evidence.typeArgumentsGround evidence.constArgumentsGround
    evidence.requirements

/-- Explicit generic struct construction: constructor selection and source
    generic syntax are coupled to one nominal-instantiation record. -/
structure StructExplicitEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path : Surface.Path)
    (constructor : SurfaceElaboration.StructConstructorScheme)
    (inner : Static.SymbolicSubstitution)
    (symbolicTypeArguments : List Static.Ty)
    (symbolicConstArguments : List Static.Const)
    (resolved : Static.NominalInstance) : Type where
  selected : SurfaceElaboration.SelectsStructConstructor
    symbolic.globals path constructor
  explicitArguments : ExplicitGenericArgumentsRetain symbolic.globals path
    constructor.genericParameters inner
  nominal : NominalInstantiationEvidence outer concrete symbolic
    constructor.genericParameters constructor.requirements constructor.declaration
    constructor.sourceType .structure inner symbolicTypeArguments
    symbolicConstArguments resolved

theorem StructExplicitEvidence.symbolicInference
    (evidence : StructExplicitEvidence outer concrete symbolic path constructor
      inner symbolicTypeArguments symbolicConstArguments resolved)
    (fields : SymbolicStructFieldsCheck symbolic inner constructor.fields
      surfaceFields) :
    SymbolicExprInfers symbolic (.structValue path surfaceFields)
      (.nominal constructor.sourceType symbolicTypeArguments
        symbolicConstArguments) :=
  .structExplicit evidence.selected evidence.explicitArguments
    evidence.nominal.arguments evidence.nominal.requirements.symbolic fields

/-- Generic struct construction inferred from its field expressions. -/
structure StructInferenceEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path : Surface.Path)
    (constructor : SurfaceElaboration.StructConstructorScheme)
    (inner : Static.SymbolicSubstitution)
    (symbolicTypeArguments : List Static.Ty)
    (symbolicConstArguments : List Static.Const)
    (resolved : Static.NominalInstance) : Type where
  selected : SurfaceElaboration.SelectsStructConstructor
    symbolic.globals path constructor
  implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path
  generic : constructor.genericParameters ≠ []
  determined : SurfaceElaboration.TypesDetermineGenericParameters
    (constructor.fields.map fun field => field.type)
    constructor.genericParameters
  nominal : NominalInstantiationEvidence outer concrete symbolic
    constructor.genericParameters constructor.requirements constructor.declaration
    constructor.sourceType .structure inner symbolicTypeArguments
    symbolicConstArguments resolved

theorem StructInferenceEvidence.symbolicInference
    (evidence : StructInferenceEvidence outer concrete symbolic path constructor
      inner symbolicTypeArguments symbolicConstArguments resolved)
    (fields : SymbolicStructFieldsInfer symbolic inner constructor.fields
      surfaceFields) :
    SymbolicExprInfers symbolic (.structValue path surfaceFields)
      (.nominal constructor.sourceType symbolicTypeArguments
        symbolicConstArguments) :=
  .structInferred evidence.selected evidence.implicitArguments evidence.generic
    evidence.determined fields evidence.nominal.arguments
    evidence.nominal.requirements.symbolic

/-- Closed struct construction.  The nominal evidence fixes the empty ordered
    argument vector even though its substitution may contain unrelated outer
    entries. -/
structure StructNongenericEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path : Surface.Path)
    (constructor : SurfaceElaboration.StructConstructorScheme)
    (inner : Static.SymbolicSubstitution)
    (resolved : Static.NominalInstance) : Type where
  selected : SurfaceElaboration.SelectsStructConstructor
    symbolic.globals path constructor
  implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path
  nongeneric : constructor.genericParameters = []
  nominal : NominalInstantiationEvidence outer concrete symbolic
    constructor.genericParameters constructor.requirements constructor.declaration
    constructor.sourceType .structure inner [] [] resolved

theorem StructNongenericEvidence.symbolicInference
    (evidence : StructNongenericEvidence outer concrete symbolic path constructor
      inner resolved)
    (fields : SymbolicStructFieldsCheck symbolic inner constructor.fields
      surfaceFields) :
    SymbolicExprInfers symbolic (.structValue path surfaceFields)
      (.nominal constructor.sourceType [] []) :=
  .structNongeneric evidence.selected evidence.implicitArguments
    evidence.nongeneric evidence.nominal.requirements.symbolic fields

/-- Explicit generic enum-variant construction. -/
structure VariantExplicitEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path : Surface.Path)
    (constructor : SurfaceElaboration.VariantConstructorScheme)
    (inner : Static.SymbolicSubstitution)
    (symbolicTypeArguments : List Static.Ty)
    (symbolicConstArguments : List Static.Const)
    (resolved : Static.NominalInstance) : Type where
  selected : SelectsSymbolicVariantConstructor symbolic path constructor
  notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none
  explicitArguments : ExplicitGenericArgumentsRetain symbolic.globals path
    constructor.genericParameters inner
  nominal : NominalInstantiationEvidence outer concrete symbolic
    constructor.genericParameters constructor.requirements
    constructor.nominalDeclaration constructor.sourceType .enumeration inner
    symbolicTypeArguments symbolicConstArguments resolved

theorem VariantExplicitEvidence.symbolicInference
    (evidence : VariantExplicitEvidence outer concrete symbolic path constructor
      inner symbolicTypeArguments symbolicConstArguments resolved)
    (payload : SymbolicExprsSubstitutedCheck symbolic inner surfaceArguments
      constructor.payload) :
    SymbolicExprInfers symbolic (.call (.path path) surfaceArguments)
      (.nominal constructor.sourceType symbolicTypeArguments
        symbolicConstArguments) :=
  .variantExplicit evidence.selected evidence.notIntrinsic evidence.explicitArguments
    evidence.nominal.arguments evidence.nominal.requirements.symbolic payload

/-- Generic enum-variant construction inferred from payload expressions. -/
structure VariantInferenceEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path : Surface.Path)
    (constructor : SurfaceElaboration.VariantConstructorScheme)
    (inner : Static.SymbolicSubstitution)
    (observedTypes : List Static.Ty)
    (symbolicTypeArguments : List Static.Ty)
    (symbolicConstArguments : List Static.Const)
    (resolved : Static.NominalInstance) : Type where
  selected : SelectsSymbolicVariantConstructor symbolic path constructor
  notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none
  implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path
  generic : constructor.genericParameters ≠ []
  determined : SurfaceElaboration.TypesDetermineGenericParameters
    constructor.payload constructor.genericParameters
  typeMatches : Static.TypesSymbolicallyMatch inner constructor.payload
    observedTypes
  nominal : NominalInstantiationEvidence outer concrete symbolic
    constructor.genericParameters constructor.requirements
    constructor.nominalDeclaration constructor.sourceType .enumeration inner
    symbolicTypeArguments symbolicConstArguments resolved

theorem VariantInferenceEvidence.symbolicInference
    (evidence : VariantInferenceEvidence outer concrete symbolic path constructor
      inner observedTypes symbolicTypeArguments symbolicConstArguments resolved)
    (payload : SymbolicExprsInfer symbolic surfaceArguments observedTypes) :
    SymbolicExprInfers symbolic (.call (.path path) surfaceArguments)
      (.nominal constructor.sourceType symbolicTypeArguments
        symbolicConstArguments) :=
  .variantInferred evidence.selected evidence.notIntrinsic
    evidence.implicitArguments evidence.generic evidence.determined payload
    evidence.typeMatches evidence.nominal.arguments
    evidence.nominal.requirements.symbolic

/-- Closed enum-variant construction. -/
structure VariantNongenericEvidence
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (symbolic : SymbolicBodyContext)
    (path : Surface.Path)
    (constructor : SurfaceElaboration.VariantConstructorScheme)
    (inner : Static.SymbolicSubstitution)
    (resolved : Static.NominalInstance) : Type where
  selected : SelectsSymbolicVariantConstructor symbolic path constructor
  notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none
  implicitArguments : SurfaceElaboration.PathHasNoGenericArguments path
  nongeneric : constructor.genericParameters = []
  nominal : NominalInstantiationEvidence outer concrete symbolic
    constructor.genericParameters constructor.requirements
    constructor.nominalDeclaration constructor.sourceType .enumeration inner
    [] [] resolved

theorem VariantNongenericEvidence.symbolicInference
    (evidence : VariantNongenericEvidence outer concrete symbolic path constructor
      inner resolved)
    (payload : SymbolicExprsSubstitutedCheck symbolic inner surfaceArguments
      constructor.payload) :
    SymbolicExprInfers symbolic (.call (.path path) surfaceArguments)
      (.nominal constructor.sourceType [] []) :=
  .variantNongeneric evidence.selected evidence.notIntrinsic
    evidence.implicitArguments evidence.nongeneric payload
    evidence.nominal.requirements.symbolic

/- The first recursive specialization kernel. Its result indices expose the
    exact grounded type and core expression, so a parent occurrence cannot use
    a different lowering of the same child. More expression constructors join
    this mutual relation as their non-recursive selection evidence is factored
    from their children. -/
mutual
  inductive ExprInferenceDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        Surface.Expr → Static.Ty → Static.GroundTy → Core.Expr → Prop where
    | literal
        (lowered : Elaboration.LiteralElaborates symbolic.globals.target literal
          (Elaboration.literalDefaultType literal) coreExpression) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.literal literal)
          (.scalar (literalDefaultScalar literal))
          (.scalar (literalDefaultScalar literal)) coreExpression
    | local
        (single : SurfaceElaboration.singleNamePath? path = some name)
        (symbolicResolved : ResolvesSymbolicLocal symbolic.locals name
          symbolicBinding)
        (concreteResolved : SurfaceElaboration.ResolvesLocal concrete.locals name
          concreteBinding)
        (typeGrounds : symbolicBinding.type.instantiate outer =
          some concreteBinding.type) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.path path) symbolicBinding.type concreteBinding.type
          (.local concreteBinding.id)
    | selfValue
        (symbolicResolved : ResolvesSymbolicLocal symbolic.locals "self"
          symbolicBinding)
        (concreteResolved : SurfaceElaboration.ResolvesLocal concrete.locals "self"
          concreteBinding)
        (typeGrounds : symbolicBinding.type.instantiate outer =
          some concreteBinding.type) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts .selfValue symbolicBinding.type concreteBinding.type
          (.local concreteBinding.id)
    | constant
        (symbolicSelected : SourceWellFormed.SelectsConstant
          symbolic.scopeContext path entry)
        (concreteSelected : SurfaceElaboration.ResolvesConstant concrete path entry) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.path path) entry.type.toTy entry.type
          (.constant entry.constant)
    | signedMinimumLiteral
        (lowered : Elaboration.SignedMinimumLiteralElaborates
          symbolic.globals.target text .i32 coreExpression) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.unary .negative (.literal (.integer text)))
          (.scalar (.signed .i32)) (.scalar (.signed .i32)) coreExpression
    | array
        (head : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceHead elementType groundElement coreHead)
        (tail : ExprListCheckingDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceTail
          (List.replicate surfaceTail.length elementType)
          (List.replicate surfaceTail.length groundElement) coreTail)
        (elementCore : groundElement.toCore concrete.monomorphization =
          some coreElementType) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.array (surfaceHead :: surfaceTail))
          (.array elementType (.literal (surfaceHead :: surfaceTail).length))
          (.array groundElement (surfaceHead :: surfaceTail).length)
          (.array coreElementType (coreHead :: coreTail))
    | unaryScalar
        (operand : ExprInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceOperand
          (.scalar inputType) (.scalar inputType) coreOperand)
        (typed : Typing.UnaryOpHasType (SurfaceElaboration.lowerUnaryOp op)
          (.scalar inputType) (.scalar outputType)) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.unary op surfaceOperand) (.scalar outputType)
          (.scalar outputType)
          (.unary (SurfaceElaboration.lowerUnaryOp op) coreOperand)
    | binaryExact
        (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceLeft (.scalar leftType)
          (.scalar leftType) coreLeft)
        (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceRight (.scalar rightType)
          (.scalar rightType) coreRight)
        (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
          (.scalar leftType) (.scalar rightType) (.scalar outputType)) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.binary op surfaceLeft surfaceRight)
          (.scalar outputType) (.scalar outputType)
          (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft coreRight)
    | binaryNullPointerRight
        (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceLeft (.scalar .rawPtr)
          (.scalar .rawPtr) coreLeft)
        (null : Elaboration.LiteralElaborates symbolic.globals.target
          (.integer text) (.scalar .rawPtr) coreRight)
        (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
          (.scalar .rawPtr) (.scalar .rawPtr) (.scalar outputType)) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.binary op surfaceLeft (.literal (.integer text)))
          (.scalar outputType) (.scalar outputType)
          (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft coreRight)
    | binaryNullPointerLeft
        (null : Elaboration.LiteralElaborates symbolic.globals.target
          (.integer text) (.scalar .rawPtr) coreLeft)
        (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceRight (.scalar .rawPtr)
          (.scalar .rawPtr) coreRight)
        (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
          (.scalar .rawPtr) (.scalar .rawPtr) (.scalar outputType)) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.binary op (.literal (.integer text)) surfaceRight)
          (.scalar outputType) (.scalar outputType)
          (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft coreRight)
    | binaryRightCast
        (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceLeft (.scalar leftType)
          (.scalar leftType) coreLeft)
        (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceRight (.scalar rightType)
          (.scalar rightType) coreRight)
        (different : rightType ≠ leftType)
        (notPreferred : ¬ Typing.RightDominatesBinary leftType rightType)
        (conversion : Typing.ScalarCast rightType leftType)
        (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
          (.scalar leftType) (.scalar leftType) (.scalar outputType)) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.binary op surfaceLeft surfaceRight)
          (.scalar outputType) (.scalar outputType)
          (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft
            (.cast leftType coreRight))
    | binaryLeftCast
        (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceLeft (.scalar leftType)
          (.scalar leftType) coreLeft)
        (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceRight (.scalar rightType)
          (.scalar rightType) coreRight)
        (preferred : Typing.RightDominatesBinary leftType rightType)
        (conversion : Typing.ScalarCast leftType rightType)
        (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
          (.scalar rightType) (.scalar rightType) (.scalar outputType)) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.binary op surfaceLeft surfaceRight)
          (.scalar outputType) (.scalar outputType)
          (.binary (SurfaceElaboration.lowerBinaryOp op) (.cast rightType coreLeft)
            coreRight)
    | printI32
        (builtin : SurfaceElaboration.builtinIntrinsic? path = some .printI32)
        (argument : ExprCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArgument
          (.scalar (.signed .i32)) (.scalar (.signed .i32)) coreArgument) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) [surfaceArgument]) .unit .unit
          (.intrinsic .printI32 coreArgument)
    | assert
        (builtin : SurfaceElaboration.builtinIntrinsic? path = some .assert)
        (argument : ExprCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArgument
          (.scalar .bool) (.scalar .bool) coreArgument) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) [surfaceArgument]) .unit .unit
          (.intrinsic .assert coreArgument)
    | i32ArrayDataPtr
        (builtin : SurfaceElaboration.builtinIntrinsic? path =
          some .i32ArrayDataPtr)
        (argument : ExprCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArgument
          (.array (.scalar (.signed .i32)) length)
          (.array (.scalar (.signed .i32)) groundLength) coreArgument) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) [surfaceArgument])
          (.scalar .rawPtr) (.scalar .rawPtr) (.i32ArrayDataPtr coreArgument)
    | indexArray
        (base : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceBase (.array elementType length)
          (.array groundElement groundLength) coreBase)
        (elementGrounds : elementType.instantiate outer = some groundElement)
        (index : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceIndex indexType groundIndex coreIndex)
        (integer : SymbolicIntegerType indexType) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.index surfaceBase surfaceIndex) elementType
          groundElement (.index coreBase coreIndex)
    | indexSlice
        (base : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceBase (.slice elementType)
          (.slice groundElement) coreBase)
        (elementGrounds : elementType.instantiate outer = some groundElement)
        (index : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceIndex indexType groundIndex coreIndex)
        (integer : SymbolicIntegerType indexType) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.index surfaceBase surfaceIndex) elementType
          groundElement (.index coreBase coreIndex)
    | field
        (base : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceBase sourceReceiver sourceGround
          sourceCore)
        (memberBase : SymbolicMemberBase sourceReceiver receiverType)
        (memberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
          sourceGround sourceCore groundReceiver coreBase)
        (receiverGrounds : receiverType.instantiate outer = some groundReceiver)
        (symbolicSelected : SelectsSymbolicField symbolic receiverType name
          fieldType)
        (concreteSelected : SurfaceElaboration.SelectsField concrete
          groundReceiver name entry)
        (fieldGrounds : fieldType.instantiate outer = some entry.type) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.member surfaceBase name) fieldType entry.type
          (.field coreBase entry.field)
    | structExplicit
        (evidence : StructExplicitEvidence outer concrete symbolic path
          constructor inner symbolicTypeArguments symbolicConstArguments
          resolved)
        (fields : StructFieldsCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner
          constructor.fields surfaceFields coreFields) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.structValue path surfaceFields)
          (.nominal constructor.sourceType symbolicTypeArguments
            symbolicConstArguments)
          (.nominal constructor.sourceType resolved.typeArguments
            resolved.constArguments)
          (.structValue resolved.coreType coreFields)
    | structInferred
        (evidence : StructInferenceEvidence outer concrete symbolic path
          constructor inner symbolicTypeArguments symbolicConstArguments
          resolved)
        (fields : StructFieldsInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner
          constructor.fields surfaceFields coreFields) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.structValue path surfaceFields)
          (.nominal constructor.sourceType symbolicTypeArguments
            symbolicConstArguments)
          (.nominal constructor.sourceType resolved.typeArguments
            resolved.constArguments)
          (.structValue resolved.coreType coreFields)
    | structNongeneric
        (evidence : StructNongenericEvidence outer concrete symbolic path
          constructor inner resolved)
        (fields : StructFieldsCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner
          constructor.fields surfaceFields coreFields) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.structValue path surfaceFields)
          (.nominal constructor.sourceType [] [])
          (.nominal constructor.sourceType resolved.typeArguments
            resolved.constArguments)
          (.structValue resolved.coreType coreFields)
    | variantExplicit
        (evidence : VariantExplicitEvidence outer concrete symbolic path
          constructor inner symbolicTypeArguments symbolicConstArguments
          resolved)
        (payload : ExprListSubstitutedCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner surfaceArguments
          constructor.payload coreArguments) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) surfaceArguments)
          (.nominal constructor.sourceType symbolicTypeArguments
            symbolicConstArguments)
          (.nominal constructor.sourceType resolved.typeArguments
            resolved.constArguments)
          (.enumValue resolved.coreType constructor.variant coreArguments)
    | variantInferred
        (evidence : VariantInferenceEvidence outer concrete symbolic path
          constructor inner observedTypes symbolicTypeArguments
          symbolicConstArguments resolved)
        (payload : ExprListInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArguments
          observedTypes groundPayload coreArguments) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) surfaceArguments)
          (.nominal constructor.sourceType symbolicTypeArguments
            symbolicConstArguments)
          (.nominal constructor.sourceType resolved.typeArguments
            resolved.constArguments)
          (.enumValue resolved.coreType constructor.variant coreArguments)
    | variantNongeneric
        (evidence : VariantNongenericEvidence outer concrete symbolic path
          constructor inner resolved)
        (payload : ExprListSubstitutedCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner surfaceArguments
          constructor.payload coreArguments) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) surfaceArguments)
          (.nominal constructor.sourceType [] [])
          (.nominal constructor.sourceType resolved.typeArguments
            resolved.constArguments)
          (.enumValue resolved.coreType constructor.variant coreArguments)
    | matchValue
        (scrutinee : ExprInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceScrutinee
          symbolicScrutinee groundScrutinee coreScrutinee)
        (resultGrounds : symbolicResult.instantiate outer = some groundResult)
        (arms : MatchArmsInferenceDerivationSpecializes outer
          groundEnclosingReturn
          symbolic concrete contexts concrete.nextExpressionLocalId
          symbolicScrutinee symbolicResult
          groundScrutinee groundResult surfaceArms coreArms) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.matchValue surfaceScrutinee surfaceArms)
          symbolicResult groundResult (.matchValue coreScrutinee coreArms)
    | directCallInferred
        (evidence : DirectCallInferenceEvidence outer concrete symbolic path
          observedTypes returnType scheme inner resolved)
        (arguments : ExprListInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArguments
          observedTypes resolved.parameterTypes coreArguments) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) surfaceArguments) returnType
          resolved.returnType (.call resolved.function coreArguments)
    | directCallExplicit
        (evidence : DirectCallExplicitEvidence outer concrete symbolic path
          parameterTypes returnType scheme inner resolved)
        (arguments : ExprListCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArguments
          parameterTypes resolved.parameterTypes coreArguments) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) surfaceArguments) returnType
          resolved.returnType (.call resolved.function coreArguments)
    | directCallNongeneric
        (evidence : DirectCallNongenericEvidence outer concrete symbolic path
          scheme resolved)
        (arguments : ExprListCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArguments
          scheme.parameterTypes resolved.parameterTypes coreArguments) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) surfaceArguments)
          scheme.returnType resolved.returnType
          (.call resolved.function coreArguments)
    | associatedCallInferred
        (evidence : AssociatedCallInferenceEvidence outer concrete symbolic path
          ownerPath name receiverType sourceParameterTypes observedTypes
          groundArgumentTypes returnType scheme inner resolved)
        (arguments : ExprListInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArguments
          observedTypes groundArgumentTypes coreArguments) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) surfaceArguments) returnType
          resolved.returnType (.call resolved.function coreArguments)
    | associatedCallContextual
        (evidence : AssociatedCallContextualEvidence outer concrete symbolic path
          ownerPath name receiverType sourceParameterTypes expectedArgumentTypes
          groundArgumentTypes returnType scheme inner resolved)
        (arguments : ExprListCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArguments
          expectedArgumentTypes groundArgumentTypes coreArguments) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) surfaceArguments) returnType
          resolved.returnType (.call resolved.function coreArguments)
    | methodCallInferred
        (evidence : MethodCallInferenceEvidence outer concrete symbolic
          receiverType name observedTypes returnType scheme inner resolved)
        (receiver : ExprInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceReceiver
          sourceReceiver sourceGround sourceCore)
        (memberBase : SymbolicMemberBase sourceReceiver receiverType)
        (memberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
          sourceGround sourceCore resolved.receiverType receiverCore)
        (arguments : ExprListInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArguments
          observedTypes resolved.argumentTypes coreArguments)
        (receiverArgument : Elaboration.ReceiverArgumentLowers
          concrete.monomorphization resolved.receiverMode resolved.receiverType
          receiverCore receiverArgumentCore) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.member surfaceReceiver name) surfaceArguments)
          returnType resolved.returnType
          (.call resolved.function (receiverArgumentCore :: coreArguments))
    | assign
        (place : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfacePlace placeType groundPlace corePlace)
        (value : ExprCheckingDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceValue placeType groundPlace coreValue)
        (coreGrounds : groundPlace.toCore concrete.monomorphization =
          some corePlaceType)
        (typed : SymbolicAssignOpHasType op placeType) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.assign op surfacePlace surfaceValue) .unit .unit
          (.assign (SurfaceElaboration.lowerAssignOp op) corePlace coreValue)
    | methodCallContextual
        (evidence : MethodCallContextualEvidence outer concrete symbolic
          receiverType name expectedArgumentTypes returnType scheme inner resolved)
        (receiver : ExprInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceReceiver
          sourceReceiver sourceGround sourceCore)
        (memberBase : SymbolicMemberBase sourceReceiver receiverType)
        (memberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
          sourceGround sourceCore resolved.receiverType receiverCore)
        (arguments : ExprListCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceArguments
          expectedArgumentTypes resolved.argumentTypes coreArguments)
        (receiverArgument : Elaboration.ReceiverArgumentLowers
          concrete.monomorphization resolved.receiverMode resolved.receiverType
          receiverCore receiverArgumentCore) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.member surfaceReceiver name) surfaceArguments)
          returnType resolved.returnType
          (.call resolved.function (receiverArgumentCore :: coreArguments))

  inductive ExprListInferenceDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        List Surface.Expr → List Static.Ty →
        List Static.GroundTy → List Core.Expr → Prop where
    | nil : ExprListInferenceDerivationSpecializes outer groundEnclosingReturn
        symbolic concrete contexts [] [] [] []
    | cons
        (head : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceHead symbolicHead groundHead coreHead)
        (tail : ExprListInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceTail
          symbolicTail groundTail coreTail) :
        ExprListInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts (surfaceHead :: surfaceTail)
          (symbolicHead :: symbolicTail) (groundHead :: groundTail)
          (coreHead :: coreTail)

  inductive ExprCheckingDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        Surface.Expr → Static.Ty → Static.GroundTy → Core.Expr → Prop where
    | exact
        (inferred : ExprInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surface symbolicType
          groundType coreExpression)
        (symbolicInferred : SymbolicExprInfers symbolic surface symbolicType)
        (typeGrounds : symbolicType.instantiate outer = some groundType)
        (concreteLowered : SurfaceElaboration.ExprLowers concrete surface
          groundType coreExpression) :
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface symbolicType groundType coreExpression
    | literal
        (lowered : Elaboration.LiteralElaborates symbolic.globals.target literal
          (.scalar scalarType) coreExpression) :
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.literal literal) (.scalar scalarType)
          (.scalar scalarType) coreExpression
    | signedMinimumLiteral
        (lowered : Elaboration.SignedMinimumLiteralElaborates
          symbolic.globals.target text signedType coreExpression) :
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.unary .negative (.literal (.integer text)))
          (.scalar (.signed signedType)) (.scalar (.signed signedType))
          coreExpression
    | unaryLiteral
        (lowered : Elaboration.LiteralElaborates symbolic.globals.target literal
          (.scalar scalarType) coreOperand)
        (typed : Typing.UnaryOpHasType (SurfaceElaboration.lowerUnaryOp op)
          (.scalar scalarType) (.scalar scalarType)) :
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.unary op (.literal literal))
          (.scalar scalarType) (.scalar scalarType)
          (.unary (SurfaceElaboration.lowerUnaryOp op) coreOperand)
    | array
        (elements : ExprListCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceElements
          (List.replicate surfaceElements.length elementType)
          (List.replicate surfaceElements.length groundElement) coreElements)
        (elementGrounds : elementType.instantiate outer = some groundElement)
        (elementCore : groundElement.toCore concrete.monomorphization =
          some coreElementType) :
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.array surfaceElements)
          (.array elementType (.literal surfaceElements.length))
          (.array groundElement surfaceElements.length)
          (.array coreElementType coreElements)
    | scalarCast
        (inferred : ExprInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceExpression
          (.scalar sourceType) (.scalar sourceType) coreExpression)
        (symbolicInferred : SymbolicExprInfers symbolic surfaceExpression
          (.scalar sourceType))
        (concreteInferred : SurfaceElaboration.ExprLowers concrete
          surfaceExpression (.scalar sourceType) coreExpression)
        (notContextualLiteral : ¬ SurfaceElaboration.ContextualScalarLiteralApplies
          symbolic.globals.target surfaceExpression targetType)
        (different : sourceType ≠ targetType)
        (conversion : Typing.ScalarCast sourceType targetType) :
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpression (.scalar targetType)
          (.scalar targetType) (.cast targetType coreExpression)
    | arrayToSlice
        (array : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceExpression (.array elementType length)
          (.array groundElement groundLength) coreArray)
        (symbolicInferred : SymbolicExprInfers symbolic surfaceExpression
          (.array elementType length))
        (concreteInferred : SurfaceElaboration.ExprLowers concrete
          surfaceExpression (.array groundElement groundLength) coreArray)
        (elementGrounds : elementType.instantiate outer = some groundElement)
        (elementCore : groundElement.toCore concrete.monomorphization =
          some coreElementType) :
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpression (.slice elementType)
          (.slice groundElement) (.arrayToSlice coreElementType coreArray)
    | structValue
        (selected : SurfaceElaboration.SelectsStructConstructor
          symbolic.globals path constructor)
        (expected : expectedType = .nominal constructor.sourceType
          symbolicTypeArguments symbolicConstArguments)
        (arguments : Static.SymbolicArgumentsBound inner
          constructor.genericParameters symbolicTypeArguments
          symbolicConstArguments)
        (typeArgumentsGround : Static.instantiateTypes outer
          symbolicTypeArguments = some groundTypeArguments)
        (constArgumentsGround : Static.instantiateConstants outer
          symbolicConstArguments = some groundConstArguments)
        (pathArguments : SymbolicPathArgumentsCompatible symbolic.globals path
          constructor.genericParameters inner)
        (requirements : Static.SymbolicRequirementsGround
          symbolic.globals.implementations symbolic.assumptions outer inner
          constructor.requirements)
        (artifact : NominalArtifactDemand concrete constructor.declaration
          constructor.sourceType .structure groundTypeArguments
          groundConstArguments resolved)
        (fields : StructFieldsCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner
          constructor.fields surfaceFields coreFields)
        (symbolicFields : SymbolicStructFieldsCheck symbolic inner
          constructor.fields surfaceFields)
        (concreteFields : SurfaceElaboration.StructSchemeFieldsCheck concrete
          (inner.composeGround outer) constructor.fields surfaceFields coreFields) :
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.structValue path surfaceFields) expectedType
          (.nominal constructor.sourceType resolved.typeArguments
            resolved.constArguments)
          (.structValue resolved.coreType coreFields)
    | variantCall
        (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
        (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
        (expected : expectedType = .nominal constructor.sourceType
          symbolicTypeArguments symbolicConstArguments)
        (arguments : Static.SymbolicArgumentsBound inner
          constructor.genericParameters symbolicTypeArguments
          symbolicConstArguments)
        (typeArgumentsGround : Static.instantiateTypes outer
          symbolicTypeArguments = some groundTypeArguments)
        (constArgumentsGround : Static.instantiateConstants outer
          symbolicConstArguments = some groundConstArguments)
        (pathArguments : SymbolicPathArgumentsCompatible symbolic.globals path
          constructor.genericParameters inner)
        (requirements : Static.SymbolicRequirementsGround
          symbolic.globals.implementations symbolic.assumptions outer inner
          constructor.requirements)
        (artifact : NominalArtifactDemand concrete constructor.nominalDeclaration
          constructor.sourceType .enumeration groundTypeArguments
          groundConstArguments resolved)
        (payload : ExprListSubstitutedCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner surfaceArguments
          constructor.payload coreArguments)
        (symbolicPayload : SymbolicExprsSubstitutedCheck symbolic inner
          surfaceArguments constructor.payload)
        (concretePayload : SurfaceElaboration.SymbolicExprsCheck concrete
          (inner.composeGround outer) surfaceArguments constructor.payload
          coreArguments) :
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) surfaceArguments) expectedType
          (.nominal constructor.sourceType resolved.typeArguments
            resolved.constArguments)
          (.enumValue resolved.coreType constructor.variant coreArguments)

  inductive ExprListCheckingDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        List Surface.Expr → List Static.Ty →
        List Static.GroundTy → List Core.Expr → Prop where
    | nil : ExprListCheckingDerivationSpecializes outer groundEnclosingReturn
        symbolic concrete contexts [] [] [] []
    | cons
        (head : ExprCheckingDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceHead symbolicHead groundHead coreHead)
        (tail : ExprListCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceTail
          symbolicTail groundTail coreTail) :
        ExprListCheckingDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts (surfaceHead :: surfaceTail)
          (symbolicHead :: symbolicTail) (groundHead :: groundTail)
          (coreHead :: coreTail)

  inductive ExprListSubstitutedCheckingDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        Static.SymbolicSubstitution → List Surface.Expr → List Static.Ty →
        List Core.Expr → Prop where
    | nil : ExprListSubstitutedCheckingDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts inner [] [] []
    | cons
        (substituted : originalHead.substitute inner = some expectedHead)
        (head : ExprCheckingDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceHead expectedHead groundHead coreHead)
        (tail : ExprListSubstitutedCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner surfaceTail
          originalTail coreTail)
        (tailSymbolic : SymbolicExprsSubstitutedCheck symbolic inner surfaceTail
          originalTail)
        (tailConcrete : SurfaceElaboration.SymbolicExprsCheck concrete
          (inner.composeGround outer) surfaceTail originalTail coreTail) :
        ExprListSubstitutedCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner
          (surfaceHead :: surfaceTail) (originalHead :: originalTail)
          (coreHead :: coreTail)

  inductive StructFieldsCheckingDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        Static.SymbolicSubstitution →
        List SurfaceElaboration.StructFieldScheme →
        List (Surface.Name × Surface.Expr) → List Core.Expr → Prop where
    | nil : StructFieldsCheckingDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts inner [] [] []
    | cons
        (removed : SurfaceElaboration.RemovesNamedField field.name surfaceFields
          surfaceValue remainder)
        (substituted : field.type.substitute inner = some expectedType)
        (value : ExprCheckingDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceValue expectedType groundType coreValue)
        (tail : StructFieldsCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner fieldTail
          remainder coreTail)
        (tailSymbolic : SymbolicStructFieldsCheck symbolic inner fieldTail
          remainder)
        (tailConcrete : SurfaceElaboration.StructSchemeFieldsCheck concrete
          (inner.composeGround outer) fieldTail remainder coreTail) :
        StructFieldsCheckingDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts inner (field :: fieldTail) surfaceFields
          (coreValue :: coreTail)

  inductive StructFieldsInferenceDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        Static.SymbolicSubstitution →
        List SurfaceElaboration.StructFieldScheme →
        List (Surface.Name × Surface.Expr) → List Core.Expr → Prop where
    | nil : StructFieldsInferenceDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts inner [] [] []
    | cons
        (removed : SurfaceElaboration.RemovesNamedField field.name surfaceFields
          surfaceValue remainder)
        (value : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceValue actualType groundType coreValue)
        (matched : Static.TySymbolicallyMatches inner field.type actualType)
        (tail : StructFieldsInferenceDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts inner fieldTail
          remainder coreTail)
        (tailSymbolic : SymbolicStructFieldsInfer symbolic inner fieldTail
          remainder)
        (tailConcrete : SurfaceElaboration.StructSchemeFieldsInfer concrete
          (inner.composeGround outer) fieldTail remainder coreTail) :
        StructFieldsInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts inner (field :: fieldTail) surfaceFields
          (coreValue :: coreTail)

  inductive PlaceDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        Surface.Expr → Static.Ty → Static.GroundTy → Core.Place → Prop where
    | local
        (single : SurfaceElaboration.singleNamePath? path = some name)
        (symbolicResolved : ResolvesSymbolicLocal symbolic.locals name
          symbolicBinding)
        (concreteResolved : SurfaceElaboration.ResolvesLocal concrete.locals name
          concreteBinding)
        (typeGrounds : symbolicBinding.type.instantiate outer =
          some concreteBinding.type) :
        PlaceDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts (.path path) symbolicBinding.type concreteBinding.type
          (.local concreteBinding.id)
    | selfValue
        (symbolicResolved : ResolvesSymbolicLocal symbolic.locals "self"
          symbolicBinding)
        (concreteResolved : SurfaceElaboration.ResolvesLocal concrete.locals "self"
          concreteBinding)
        (typeGrounds : symbolicBinding.type.instantiate outer =
          some concreteBinding.type) :
        PlaceDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts .selfValue symbolicBinding.type concreteBinding.type
          (.local concreteBinding.id)
    | field
        (base : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase receiverType groundReceiver coreBase)
        (symbolicSelected : SelectsSymbolicField symbolic receiverType name
          fieldType)
        (concreteSelected : SurfaceElaboration.SelectsField concrete
          groundReceiver name entry)
        (fieldGrounds : fieldType.instantiate outer = some entry.type) :
        PlaceDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts (.member surfaceBase name) fieldType entry.type
          (.field coreBase entry.field)
    | indexArray
        (base : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase (.array elementType length)
          (.array groundElement groundLength) coreBase)
        (elementGrounds : elementType.instantiate outer = some groundElement)
        (lengthGrounds : length.instantiate outer = some groundLength)
        (index : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceIndex indexType groundIndex coreIndex)
        (integer : SymbolicIntegerType indexType) :
        PlaceDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts (.index surfaceBase surfaceIndex) elementType groundElement
          (.index coreBase coreIndex)
    | indexSlice
        (base : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase (.slice elementType)
          (.slice groundElement) coreBase)
        (elementGrounds : elementType.instantiate outer = some groundElement)
        (index : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts surfaceIndex indexType groundIndex coreIndex)
        (integer : SymbolicIntegerType indexType) :
        PlaceDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts (.index surfaceBase surfaceIndex) elementType groundElement
          (.index coreBase coreIndex)

  /-- Exact-output specialization for match arms. The recursive body is checked
      under exactly the symbolic and concrete locals introduced by its pattern. -/
  inductive MatchArmsDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        VarId → Static.Ty → Static.Ty → Static.GroundTy → Static.GroundTy →
        List (Surface.Pattern × Surface.Expr) →
        List (Core.Pattern × Core.Expr) → Prop where
    | nil : MatchArmsDerivationSpecializes outer groundEnclosingReturn symbolic
        concrete contexts next symbolicScrutinee symbolicResult groundScrutinee
        groundResult [] []
    | cons
        (pattern : PatternDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts next surfacePattern symbolicScrutinee
          groundScrutinee corePattern symbolicBindings concreteBindings
          patternFinal)
        (body : ExprCheckingDerivationSpecializes outer groundEnclosingReturn
          (symbolic.bindMany symbolicBindings)
          (concrete.bindLocals concreteBindings) pattern.boundContexts surfaceBody
          symbolicResult groundResult coreBody)
        (tail : MatchArmsDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts next symbolicScrutinee symbolicResult
          groundScrutinee groundResult surfaceTail coreTail) :
        MatchArmsDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts next symbolicScrutinee symbolicResult groundScrutinee
          groundResult ((surfacePattern, surfaceBody) :: surfaceTail)
          ((corePattern, coreBody) :: coreTail)

  /-- Exact specialization of a nonempty match expression. The first arm body
      is inferred and fixes both result types; the ordinary checking relation
      handles the remaining arms. -/
  inductive MatchArmsInferenceDerivationSpecializes
      (outer : Static.Substitution)
      (groundEnclosingReturn : Static.GroundTy) :
      (symbolic : SymbolicBodyContext) →
        (concrete : SurfaceElaboration.Context) →
        symbolic.Specializes outer groundEnclosingReturn concrete →
        VarId → Static.Ty → Static.Ty → Static.GroundTy →
        Static.GroundTy → List (Surface.Pattern × Surface.Expr) →
        List (Core.Pattern × Core.Expr) → Prop where
    | cons
        (pattern : PatternDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts next surfacePattern symbolicScrutinee
          groundScrutinee corePattern symbolicBindings concreteBindings
          patternFinal)
        (body : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
          (symbolic.bindMany symbolicBindings)
          (concrete.bindLocals concreteBindings) pattern.boundContexts surfaceBody
          symbolicResult groundResult coreBody)
        (tail : MatchArmsDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts next symbolicScrutinee symbolicResult
          groundScrutinee groundResult surfaceTail coreTail) :
        MatchArmsInferenceDerivationSpecializes outer groundEnclosingReturn
          symbolic concrete contexts next symbolicScrutinee symbolicResult
          groundScrutinee groundResult
          ((surfacePattern, surfaceBody) :: surfaceTail)
          ((corePattern, coreBody) :: coreTail)

end

private theorem exactSymbolicBinaryNullPointerRight
    (left : SymbolicExprInfers symbolic surfaceLeft (.scalar .rawPtr))
    (null : Elaboration.LiteralElaborates symbolic.globals.target
      (.integer text) (.scalar .rawPtr) coreRight)
    (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar .rawPtr) (.scalar .rawPtr) (.scalar outputType)) :
    SymbolicExprInfers symbolic
      (.binary op surfaceLeft (.literal (.integer text)))
      (.scalar outputType) :=
  .binaryNullPointerRight left
    ⟨.rawPtr, coreRight, rfl, null⟩ (.exact typed)

private theorem exactSymbolicBinaryNullPointerLeft
    (null : Elaboration.LiteralElaborates symbolic.globals.target
      (.integer text) (.scalar .rawPtr) coreLeft)
    (right : SymbolicExprInfers symbolic surfaceRight (.scalar .rawPtr))
    (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar .rawPtr) (.scalar .rawPtr) (.scalar outputType)) :
    SymbolicExprInfers symbolic
      (.binary op (.literal (.integer text)) surfaceRight)
      (.scalar outputType) :=
  .binaryNullPointerLeft
    ⟨.rawPtr, coreLeft, rfl, null⟩ right (.exact typed)

local macro "deriveExactSymbolicProjection" outerSubstitution:ident
    groundReturn:ident recursor:term : tactic =>
  `(tactic|
    (apply $recursor
        (outer := $outerSubstitution) (groundEnclosingReturn := $groundReturn)
        (motive_1 := fun symbolic _ _ surface symbolicType _ _ _ =>
          SymbolicExprInfers symbolic surface symbolicType)
        (motive_2 := fun symbolic _ _ surfaces symbolicTypes _ _ _ =>
          SymbolicExprsInfer symbolic surfaces symbolicTypes)
        (motive_3 := fun symbolic _ _ surface symbolicType _ _ _ =>
          SymbolicExprChecks symbolic surface symbolicType)
        (motive_4 := fun symbolic _ _ surfaces symbolicTypes _ _ _ =>
          SymbolicExprsCheck symbolic surfaces symbolicTypes)
        (motive_5 := fun symbolic _ _ inner surfaces originalTypes _ _ =>
          SymbolicExprsSubstitutedCheck symbolic inner surfaces originalTypes)
        (motive_6 := fun symbolic _ _ inner fields surfaceFields _ _ =>
          SymbolicStructFieldsCheck symbolic inner fields surfaceFields)
        (motive_7 := fun symbolic _ _ inner fields surfaceFields _ _ =>
          SymbolicStructFieldsInfer symbolic inner fields surfaceFields)
        (motive_8 := fun symbolic _ _ surface symbolicType _ _ _ =>
          SymbolicPlaceHasType symbolic surface symbolicType)
        (motive_9 := fun symbolic _ _ _ symbolicScrutinee symbolicResult _ _
            surfaceArms _ _ =>
          SymbolicMatchArmsCheck symbolic symbolicScrutinee symbolicResult
            surfaceArms)
        (motive_10 := fun symbolic _ _ _ symbolicScrutinee symbolicResult _ _
            surfaceArms _ _ =>
          SymbolicMatchArmsInfer symbolic symbolicScrutinee symbolicResult
            surfaceArms) <;>
      intros <;>
      solve_by_elim (maxDepth := 12) [
          AssociatedCallInferenceEvidence.symbolicInference,
          AssociatedCallContextualEvidence.symbolicInference,
          LiteralInfersSymbolic.default,
          SymbolicUnaryHasType.scalar,
          SymbolicBinaryHasType.exact,
          SymbolicBinaryHasType.rightCast,
          SymbolicBinaryHasType.leftCast,
          SymbolicExprInfers.literal,
          SymbolicExprInfers.signedMinimumLiteral,
          SymbolicExprInfers.local,
          SymbolicExprInfers.selfValue,
          SymbolicExprInfers.constant,
          SymbolicExprInfers.array,
          SymbolicExprInfers.unary,
          SymbolicExprInfers.binary,
          exactSymbolicBinaryNullPointerRight,
          exactSymbolicBinaryNullPointerLeft,
          SymbolicExprInfers.assign,
          SymbolicExprInfers.printI32,
          SymbolicExprInfers.assert,
          SymbolicExprInfers.i32ArrayDataPtr,
          SymbolicExprInfers.indexArray,
          SymbolicExprInfers.indexSlice,
          SymbolicExprInfers.field,
          SymbolicExprInfers.matchValue,
          StructExplicitEvidence.symbolicInference,
          StructInferenceEvidence.symbolicInference,
          StructNongenericEvidence.symbolicInference,
          VariantExplicitEvidence.symbolicInference,
          VariantInferenceEvidence.symbolicInference,
          VariantNongenericEvidence.symbolicInference,
          DirectCallInferenceEvidence.symbolicInference,
          DirectCallExplicitEvidence.symbolicInference,
          DirectCallNongenericEvidence.symbolicInference,
          MethodCallInferenceEvidence.symbolicInference,
          MethodCallContextualEvidence.symbolicInference,
          PatternDerivationSpecializes.symbolicPattern,
          SymbolicMatchArmsCheck.nil,
          SymbolicMatchArmsCheck.cons,
          SymbolicMatchArmsInfer.cons,
          SymbolicExprChecks.exact,
          SymbolicExprChecks.literal,
          SymbolicExprChecks.signedMinimumLiteral,
          SymbolicExprChecks.unaryLiteral,
          SymbolicExprChecks.array,
          SymbolicExprChecks.scalarCast,
          SymbolicExprChecks.arrayToSlice,
          SymbolicExprChecks.structValue,
          SymbolicExprChecks.variantCall,
          Static.SymbolicRequirementsGround.symbolic,
          SymbolicExprsInfer.nil,
          SymbolicExprsInfer.cons,
          SymbolicExprsCheck.nil,
          SymbolicExprsCheck.cons,
          SymbolicExprsSubstitutedCheck.nil,
          SymbolicExprsSubstitutedCheck.cons,
          SymbolicStructFieldsCheck.nil,
          SymbolicStructFieldsCheck.cons,
          SymbolicStructFieldsInfer.nil,
          SymbolicStructFieldsInfer.cons,
          SymbolicPlaceHasType.local,
          SymbolicPlaceHasType.selfValue,
          SymbolicPlaceHasType.field,
        SymbolicPlaceHasType.indexArray,
        SymbolicPlaceHasType.indexSlice]))


set_option maxHeartbeats 1000000

theorem ExprListInferenceDerivationSpecializes.symbolicInferences
    (specialized : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
      groundTypes coreExpressions) :
    SymbolicExprsInfer symbolic surfaces symbolicTypes := by
  deriveExactSymbolicProjection outer groundEnclosingReturn
    ExprListInferenceDerivationSpecializes.rec


theorem ExprInferenceDerivationSpecializes.symbolicInference
    (specialized : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface symbolicType
      groundType coreExpression) :
    SymbolicExprInfers symbolic surface symbolicType := by
  deriveExactSymbolicProjection outer groundEnclosingReturn
    ExprInferenceDerivationSpecializes.rec

theorem ExprCheckingDerivationSpecializes.symbolicCheck
    (specialized : ExprCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface symbolicType
      groundType coreExpression) :
    SymbolicExprChecks symbolic surface symbolicType := by
  deriveExactSymbolicProjection outer groundEnclosingReturn
    ExprCheckingDerivationSpecializes.rec

theorem ExprListCheckingDerivationSpecializes.symbolicChecks
    (specialized : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
      groundTypes coreExpressions) :
    SymbolicExprsCheck symbolic surfaces symbolicTypes := by
  deriveExactSymbolicProjection outer groundEnclosingReturn
    ExprListCheckingDerivationSpecializes.rec

theorem ExprListSubstitutedCheckingDerivationSpecializes.symbolicSubstituted
    (inner : Static.SymbolicSubstitution)
    (specialized : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner surfaces
      originalTypes coreExpressions) :
    SymbolicExprsSubstitutedCheck symbolic inner surfaces originalTypes := by
  deriveExactSymbolicProjection outer groundEnclosingReturn
    ExprListSubstitutedCheckingDerivationSpecializes.rec

theorem StructFieldsCheckingDerivationSpecializes.symbolicFields
    (inner : Static.SymbolicSubstitution)
    (specialized : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner fields
      surfaceFields coreFields) :
    SymbolicStructFieldsCheck symbolic inner fields surfaceFields := by
  deriveExactSymbolicProjection outer groundEnclosingReturn
    StructFieldsCheckingDerivationSpecializes.rec

theorem StructFieldsInferenceDerivationSpecializes.symbolicFields
    (inner : Static.SymbolicSubstitution)
    (specialized : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner fields
      surfaceFields coreFields) :
    SymbolicStructFieldsInfer symbolic inner fields surfaceFields := by
  deriveExactSymbolicProjection outer groundEnclosingReturn
    StructFieldsInferenceDerivationSpecializes.rec

theorem PlaceDerivationSpecializes.symbolicPlace
    (specialized : PlaceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface symbolicType groundType corePlace) :
    SymbolicPlaceHasType symbolic surface symbolicType := by
  deriveExactSymbolicProjection outer groundEnclosingReturn
    PlaceDerivationSpecializes.rec

theorem MatchArmsDerivationSpecializes.symbolicArms
    (specialized : MatchArmsDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next symbolicScrutinee symbolicResult
      groundScrutinee groundResult surfaceArms coreArms) :
    SymbolicMatchArmsCheck symbolic symbolicScrutinee symbolicResult
      surfaceArms := by
  deriveExactSymbolicProjection outer groundEnclosingReturn
    MatchArmsDerivationSpecializes.rec

theorem MatchArmsInferenceDerivationSpecializes.symbolicArms
    (specialized : MatchArmsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts next symbolicScrutinee
      symbolicResult groundScrutinee groundResult surfaceArms coreArms) :
    SymbolicMatchArmsInfer symbolic symbolicScrutinee symbolicResult
      surfaceArms := by
  deriveExactSymbolicProjection outer groundEnclosingReturn
    MatchArmsInferenceDerivationSpecializes.rec

set_option maxHeartbeats 200000


theorem SymbolicBodyContext.Specializes.target
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {substitution : Static.Substitution}
    {groundReturn : Static.GroundTy}
    (specialized : symbolic.Specializes substitution groundReturn concrete) :
    concrete.target = symbolic.globals.target := by
  rw [specialized.globals]

structure ExactInferenceConcreteProjection
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (surface : Surface.Expr)
    (symbolicType : Static.Ty)
    (groundType : Static.GroundTy)
    (core : Core.Expr) : Prop where
  typeGrounds : symbolicType.instantiate outer = some groundType
  lowers : SurfaceElaboration.ExprLowers concrete surface groundType core

structure ExactCheckingConcreteProjection
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (surface : Surface.Expr)
    (symbolicType : Static.Ty)
    (groundType : Static.GroundTy)
    (core : Core.Expr) : Prop where
  typeGrounds : symbolicType.instantiate outer = some groundType
  checks : SurfaceElaboration.ExprChecks concrete surface groundType core

structure ExactListInferenceConcreteProjection
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (surfaces : List Surface.Expr)
    (symbolicTypes : List Static.Ty)
    (groundTypes : List Static.GroundTy)
    (cores : List Core.Expr) : Prop where
  typeGrounds : Static.instantiateTypes outer symbolicTypes = some groundTypes
  lowerings : SurfaceElaboration.ExprsLower concrete surfaces groundTypes cores
  checks : SurfaceElaboration.ExprsCheck concrete surfaces groundTypes cores

structure ExactPlaceConcreteProjection
    (outer : Static.Substitution)
    (concrete : SurfaceElaboration.Context)
    (surface : Surface.Expr)
    (symbolicType : Static.Ty)
    (groundType : Static.GroundTy)
    (core : Core.Place) : Prop where
  typeGrounds : symbolicType.instantiate outer = some groundType
  lowers : SurfaceElaboration.PlaceLowers concrete surface groundType core

/- These are the concrete handlers for the mutually recursive exact
   specialization recursor.  Keeping them as ordinary theorems makes the
   recursion itself declarative and avoids exponential constructor search. -/

theorem ExactInferenceConcreteProjection.literal
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context} {literal : Surface.Literal}
    {core : Core.Expr}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (lowered : Elaboration.LiteralElaborates symbolic.globals.target literal
      (Elaboration.literalDefaultType literal) core) :
    ExactInferenceConcreteProjection outer concrete (.literal literal)
      (.scalar (literalDefaultScalar literal))
      (.scalar (literalDefaultScalar literal)) core := by
  refine ⟨rfl, ?_⟩
  rw [← contexts.target] at lowered
  exact .literal lowered (by
    simp [Static.GroundTy.toCore, literalDefaultType_eq_scalar])

theorem ExactInferenceConcreteProjection.signedMinimumLiteral
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context} {text : String} {core : Core.Expr}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (lowered : Elaboration.SignedMinimumLiteralElaborates
      symbolic.globals.target text .i32 core) :
    ExactInferenceConcreteProjection outer concrete
      (.unary .negative (.literal (.integer text)))
      (.scalar (.signed .i32)) (.scalar (.signed .i32)) core := by
  refine ⟨rfl, ?_⟩
  rw [← contexts.target] at lowered
  exact .signedMinimumLiteral lowered rfl

theorem ExactInferenceConcreteProjection.array
    (head : ExactInferenceConcreteProjection outer concrete surfaceHead
      elementType groundElement coreHead)
    (tail : SurfaceElaboration.ExprsCheck concrete surfaceTail
      (List.replicate surfaceTail.length groundElement) coreTail)
    (elementCore : groundElement.toCore concrete.monomorphization =
      some coreElementType) :
    ExactInferenceConcreteProjection outer concrete
      (.array (surfaceHead :: surfaceTail))
      (.array elementType (.literal (surfaceHead :: surfaceTail).length))
      (.array groundElement (surfaceHead :: surfaceTail).length)
      (.array coreElementType (coreHead :: coreTail)) := by
  exact ⟨by
    simp [Static.Ty.instantiate, Static.Const.instantiate, head.typeGrounds],
    .array head.lowers tail elementCore⟩

theorem ExactInferenceConcreteProjection.unaryScalar
    (operand : ExactInferenceConcreteProjection outer concrete surfaceOperand
      (.scalar inputType) (.scalar inputType) coreOperand)
    (typed : Typing.UnaryOpHasType (SurfaceElaboration.lowerUnaryOp op)
      (.scalar inputType) (.scalar outputType)) :
    ExactInferenceConcreteProjection outer concrete (.unary op surfaceOperand)
      (.scalar outputType) (.scalar outputType)
      (.unary (SurfaceElaboration.lowerUnaryOp op) coreOperand) :=
  ⟨rfl, .unary operand.lowers rfl rfl typed⟩

theorem ExactInferenceConcreteProjection.binaryExact
    (left : ExactInferenceConcreteProjection outer concrete surfaceLeft
      (.scalar leftType) (.scalar leftType) coreLeft)
    (right : ExactInferenceConcreteProjection outer concrete surfaceRight
      (.scalar rightType) (.scalar rightType) coreRight)
    (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar leftType) (.scalar rightType) (.scalar outputType)) :
    ExactInferenceConcreteProjection outer concrete
      (.binary op surfaceLeft surfaceRight) (.scalar outputType)
      (.scalar outputType)
      (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft coreRight) :=
  ⟨rfl, .binary left.lowers right.lowers rfl rfl rfl typed⟩

theorem ExactInferenceConcreteProjection.binaryNullPointerRight
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (left : ExactInferenceConcreteProjection outer concrete surfaceLeft
      (.scalar .rawPtr) (.scalar .rawPtr) coreLeft)
    (null : Elaboration.LiteralElaborates symbolic.globals.target
      (.integer text) (.scalar .rawPtr) coreRight)
    (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar .rawPtr) (.scalar .rawPtr) (.scalar outputType)) :
    ExactInferenceConcreteProjection outer concrete
      (.binary op surfaceLeft (.literal (.integer text)))
      (.scalar outputType) (.scalar outputType)
      (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft coreRight) := by
  have concreteNull : Elaboration.LiteralElaborates concrete.target
      (.integer text) (.scalar .rawPtr) coreRight := by
    rw [contexts.target]
    exact null
  exact ⟨rfl, .binaryNullPointerRight left.lowers concreteNull rfl typed⟩

theorem ExactInferenceConcreteProjection.binaryNullPointerLeft
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (null : Elaboration.LiteralElaborates symbolic.globals.target
      (.integer text) (.scalar .rawPtr) coreLeft)
    (right : ExactInferenceConcreteProjection outer concrete surfaceRight
      (.scalar .rawPtr) (.scalar .rawPtr) coreRight)
    (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar .rawPtr) (.scalar .rawPtr) (.scalar outputType)) :
    ExactInferenceConcreteProjection outer concrete
      (.binary op (.literal (.integer text)) surfaceRight)
      (.scalar outputType) (.scalar outputType)
      (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft coreRight) := by
  have concreteNull : Elaboration.LiteralElaborates concrete.target
      (.integer text) (.scalar .rawPtr) coreLeft := by
    rw [contexts.target]
    exact null
  exact ⟨rfl, .binaryNullPointerLeft concreteNull right.lowers rfl typed⟩

theorem ExactInferenceConcreteProjection.binaryRightCast
    (left : ExactInferenceConcreteProjection outer concrete surfaceLeft
      (.scalar leftType) (.scalar leftType) coreLeft)
    (right : ExactInferenceConcreteProjection outer concrete surfaceRight
      (.scalar rightType) (.scalar rightType) coreRight)
    (different : rightType ≠ leftType)
    (notPreferred : ¬ Typing.RightDominatesBinary leftType rightType)
    (conversion : Typing.ScalarCast rightType leftType)
    (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar leftType) (.scalar leftType) (.scalar outputType)) :
    ExactInferenceConcreteProjection outer concrete
      (.binary op surfaceLeft surfaceRight) (.scalar outputType)
      (.scalar outputType)
      (.binary (SurfaceElaboration.lowerBinaryOp op) coreLeft
        (.cast leftType coreRight)) :=
  ⟨rfl, .binaryRightCast left.lowers right.lowers different notPreferred
    conversion rfl typed⟩

theorem ExactInferenceConcreteProjection.binaryLeftCast
    (left : ExactInferenceConcreteProjection outer concrete surfaceLeft
      (.scalar leftType) (.scalar leftType) coreLeft)
    (right : ExactInferenceConcreteProjection outer concrete surfaceRight
      (.scalar rightType) (.scalar rightType) coreRight)
    (preferred : Typing.RightDominatesBinary leftType rightType)
    (conversion : Typing.ScalarCast leftType rightType)
    (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar rightType) (.scalar rightType) (.scalar outputType)) :
    ExactInferenceConcreteProjection outer concrete
      (.binary op surfaceLeft surfaceRight) (.scalar outputType)
      (.scalar outputType)
      (.binary (SurfaceElaboration.lowerBinaryOp op) (.cast rightType coreLeft)
        coreRight) :=
  ⟨rfl, .binaryLeftCast left.lowers right.lowers preferred conversion rfl typed⟩

theorem ExactListInferenceConcreteProjection.cons
    (head : ExactInferenceConcreteProjection outer concrete surfaceHead
      symbolicHead groundHead coreHead)
    (tail : ExactListInferenceConcreteProjection outer concrete surfaceTail
      symbolicTail groundTail coreTail) :
    ExactListInferenceConcreteProjection outer concrete
      (surfaceHead :: surfaceTail) (symbolicHead :: symbolicTail)
      (groundHead :: groundTail) (coreHead :: coreTail) :=
  ⟨by simp [Static.instantiateTypes, head.typeGrounds, tail.typeGrounds],
    .cons head.lowers tail.lowerings,
    .cons (.exact head.lowers) tail.checks⟩

theorem ExactCheckingConcreteProjection.literal
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context} {literal : Surface.Literal}
    {core : Core.Expr}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (lowered : Elaboration.LiteralElaborates symbolic.globals.target literal
      (.scalar scalarType) core) :
    ExactCheckingConcreteProjection outer concrete (.literal literal)
      (.scalar scalarType) (.scalar scalarType) core := by
  refine ⟨rfl, ?_⟩
  rw [← contexts.target] at lowered
  exact .literal _ lowered rfl

theorem ExactCheckingConcreteProjection.signedMinimumLiteral
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context} {text : String} {core : Core.Expr}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (lowered : Elaboration.SignedMinimumLiteralElaborates
      symbolic.globals.target text signedType core) :
    ExactCheckingConcreteProjection outer concrete
      (.unary .negative (.literal (.integer text)))
      (.scalar (.signed signedType)) (.scalar (.signed signedType)) core := by
  refine ⟨rfl, ?_⟩
  rw [← contexts.target] at lowered
  exact .signedMinimumLiteral lowered rfl

theorem ExactCheckingConcreteProjection.unaryLiteral
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context} {literal : Surface.Literal}
    {coreOperand : Core.Expr}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (lowered : Elaboration.LiteralElaborates symbolic.globals.target literal
      (.scalar scalarType) coreOperand)
    (typed : Typing.UnaryOpHasType (SurfaceElaboration.lowerUnaryOp op)
      (.scalar scalarType) (.scalar scalarType)) :
    ExactCheckingConcreteProjection outer concrete
      (.unary op (.literal literal)) (.scalar scalarType) (.scalar scalarType)
      (.unary (SurfaceElaboration.lowerUnaryOp op) coreOperand) := by
  refine ⟨rfl, ?_⟩
  rw [← contexts.target] at lowered
  exact .unaryLiteral lowered rfl typed

theorem ExactInferenceConcreteProjection.printI32
    (builtin : SurfaceElaboration.builtinIntrinsic? path = some .printI32)
    (argument : ExactCheckingConcreteProjection outer concrete surfaceArgument
      (.scalar (.signed .i32)) (.scalar (.signed .i32)) coreArgument) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) [surfaceArgument]) .unit .unit
      (.intrinsic .printI32 coreArgument) :=
  ⟨rfl, .printI32 rfl builtin argument.checks⟩

theorem ExactInferenceConcreteProjection.assert
    (builtin : SurfaceElaboration.builtinIntrinsic? path = some .assert)
    (argument : ExactCheckingConcreteProjection outer concrete surfaceArgument
      (.scalar .bool) (.scalar .bool) coreArgument) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) [surfaceArgument]) .unit .unit
      (.intrinsic .assert coreArgument) :=
  ⟨rfl, .assert rfl builtin argument.checks⟩

theorem ExactInferenceConcreteProjection.i32ArrayDataPtr
    (builtin : SurfaceElaboration.builtinIntrinsic? path =
      some .i32ArrayDataPtr)
    (argument : ExactCheckingConcreteProjection outer concrete surfaceArgument
      (.array (.scalar (.signed .i32)) length)
      (.array (.scalar (.signed .i32)) groundLength) coreArgument) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) [surfaceArgument]) (.scalar .rawPtr)
      (.scalar .rawPtr) (.i32ArrayDataPtr coreArgument) :=
  ⟨rfl, .i32ArrayDataPtr rfl builtin argument.checks⟩

theorem ExactInferenceConcreteProjection.indexArray
    (base : ExactInferenceConcreteProjection outer concrete surfaceBase
      (.array elementType length) (.array groundElement groundLength) coreBase)
    (elementGrounds : elementType.instantiate outer = some groundElement)
    (index : ExactInferenceConcreteProjection outer concrete surfaceIndex
      indexType groundIndex coreIndex)
    (integer : SymbolicIntegerType indexType) :
    ExactInferenceConcreteProjection outer concrete
      (.index surfaceBase surfaceIndex) elementType groundElement
      (.index coreBase coreIndex) := by
  obtain ⟨coreIndexType, indexCore, coreInteger⟩ :=
    integer.specializes index.typeGrounds
  exact ⟨elementGrounds,
    .indexArray base.lowers index.lowers indexCore coreInteger⟩

theorem ExactInferenceConcreteProjection.indexSlice
    (base : ExactInferenceConcreteProjection outer concrete surfaceBase
      (.slice elementType) (.slice groundElement) coreBase)
    (elementGrounds : elementType.instantiate outer = some groundElement)
    (index : ExactInferenceConcreteProjection outer concrete surfaceIndex
      indexType groundIndex coreIndex)
    (integer : SymbolicIntegerType indexType) :
    ExactInferenceConcreteProjection outer concrete
      (.index surfaceBase surfaceIndex) elementType groundElement
      (.index coreBase coreIndex) := by
  obtain ⟨coreIndexType, indexCore, coreInteger⟩ :=
    integer.specializes index.typeGrounds
  exact ⟨elementGrounds,
    .indexSlice base.lowers index.lowers indexCore coreInteger⟩

theorem ExactInferenceConcreteProjection.field
    (base : ExactInferenceConcreteProjection outer concrete surfaceBase
      sourceReceiver sourceGround sourceCore)
    (memberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      sourceGround sourceCore groundReceiver coreBase)
    (concreteSelected : SurfaceElaboration.SelectsField concrete
      groundReceiver name entry)
    (fieldGrounds : fieldType.instantiate outer = some entry.type) :
    ExactInferenceConcreteProjection outer concrete (.member surfaceBase name)
      fieldType entry.type (.field coreBase entry.field) :=
  ⟨fieldGrounds, .field base.lowers memberLowers concreteSelected⟩

theorem ExactInferenceConcreteProjection.matchValue
    (scrutinee : ExactInferenceConcreteProjection outer concrete surfaceScrutinee
      symbolicScrutinee groundScrutinee coreScrutinee)
    (resultGrounds : symbolicResult.instantiate outer = some groundResult)
    (arms : SurfaceElaboration.MatchArmsInfer concrete groundScrutinee
      groundResult surfaceArms coreArms) :
    ExactInferenceConcreteProjection outer concrete
      (.matchValue surfaceScrutinee surfaceArms) symbolicResult groundResult
      (.matchValue coreScrutinee coreArms) :=
  ⟨resultGrounds, .matchValue scrutinee.lowers arms⟩

private theorem symbolicExprsInfer_of_lowerings
    (lowerings : SurfaceElaboration.ExprsLower concrete surfaces groundTypes cores)
    (matched : Static.TypesMatch substitution symbolicTypes groundTypes) :
    SurfaceElaboration.SymbolicExprsInfer concrete substitution surfaces
      symbolicTypes cores := by
  induction surfaces generalizing symbolicTypes groundTypes cores with
  | nil =>
      cases lowerings
      cases matched
      exact .nil
  | cons surfaceHead surfaceTail induction =>
      cases lowerings with
      | cons head tail =>
          cases matched with
          | cons headMatch tailMatch =>
              exact .cons head headMatch (induction tail tailMatch)

theorem ExactListInferenceConcreteProjection.symbolicLowerings
    (projection : ExactListInferenceConcreteProjection outer concrete surfaces
      observedTypes groundTypes cores)
    (matched : Static.TypesSymbolicallyMatch inner patterns observedTypes) :
    SurfaceElaboration.SymbolicExprsInfer concrete (inner.composeGround outer)
      surfaces patterns cores :=
  symbolicExprsInfer_of_lowerings projection.lowerings
    (matched.composeGround (Static.TypesMatch.ofInstantiate
      projection.typeGrounds))

theorem ExactInferenceConcreteProjection.structExplicit
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : StructExplicitEvidence outer concrete symbolic path constructor
      inner symbolicTypeArguments symbolicConstArguments resolved)
    (fields : SurfaceElaboration.StructSchemeFieldsCheck concrete
      (inner.composeGround outer) constructor.fields surfaceFields coreFields) :
    ExactInferenceConcreteProjection outer concrete
      (.structValue path surfaceFields)
      (.nominal constructor.sourceType symbolicTypeArguments
        symbolicConstArguments)
      (.nominal constructor.sourceType resolved.typeArguments
        resolved.constArguments)
      (.structValue resolved.coreType coreFields) := by
  have grounded := evidence.nominal.arguments.parametersGround
    evidence.nominal.typeArgumentsGround evidence.nominal.constArgumentsGround
  exact ⟨evidence.nominal.typeGrounds,
    .structValueExplicit (contexts.selectsStructConstructor evidence.selected)
      (evidence.explicitArguments.specializes contexts grounded)
      (evidence.nominal.instantiates contexts) fields⟩

theorem ExactInferenceConcreteProjection.structInferred
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : StructInferenceEvidence outer concrete symbolic path constructor
      inner symbolicTypeArguments symbolicConstArguments resolved)
    (fields : SurfaceElaboration.StructSchemeFieldsInfer concrete
      (inner.composeGround outer) constructor.fields surfaceFields coreFields) :
    ExactInferenceConcreteProjection outer concrete
      (.structValue path surfaceFields)
      (.nominal constructor.sourceType symbolicTypeArguments
        symbolicConstArguments)
      (.nominal constructor.sourceType resolved.typeArguments
        resolved.constArguments)
      (.structValue resolved.coreType coreFields) :=
  ⟨evidence.nominal.typeGrounds,
    .structValueInferred (contexts.selectsStructConstructor evidence.selected)
      evidence.implicitArguments evidence.generic evidence.determined fields
      (evidence.nominal.instantiates contexts)⟩

theorem ExactInferenceConcreteProjection.structNongeneric
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : StructNongenericEvidence outer concrete symbolic path constructor
      inner resolved)
    (fields : SurfaceElaboration.StructSchemeFieldsCheck concrete
      (inner.composeGround outer) constructor.fields surfaceFields coreFields) :
    ExactInferenceConcreteProjection outer concrete
      (.structValue path surfaceFields) (.nominal constructor.sourceType [] [])
      (.nominal constructor.sourceType resolved.typeArguments
        resolved.constArguments)
      (.structValue resolved.coreType coreFields) :=
  ⟨evidence.nominal.typeGrounds,
    .structValueNongeneric (contexts.selectsStructConstructor evidence.selected)
      evidence.implicitArguments evidence.nongeneric
      (evidence.nominal.instantiates contexts) fields⟩

theorem ExactInferenceConcreteProjection.variantExplicit
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : VariantExplicitEvidence outer concrete symbolic path constructor
      inner symbolicTypeArguments symbolicConstArguments resolved)
    (payload : SurfaceElaboration.SymbolicExprsCheck concrete
      (inner.composeGround outer) surfaceArguments constructor.payload
      coreArguments) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) surfaceArguments)
      (.nominal constructor.sourceType symbolicTypeArguments
        symbolicConstArguments)
      (.nominal constructor.sourceType resolved.typeArguments
        resolved.constArguments)
      (.enumValue resolved.coreType constructor.variant coreArguments) := by
  have grounded := evidence.nominal.arguments.parametersGround
    evidence.nominal.typeArgumentsGround evidence.nominal.constArgumentsGround
  exact ⟨evidence.nominal.typeGrounds,
    .variantCallExplicit (contexts.selectsVariantConstructor evidence.selected)
      evidence.notIntrinsic
      (evidence.explicitArguments.specializes contexts grounded)
      (evidence.nominal.instantiates contexts) payload⟩

theorem ExactInferenceConcreteProjection.variantInferred
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : VariantInferenceEvidence outer concrete symbolic path constructor
      inner observedTypes symbolicTypeArguments symbolicConstArguments resolved)
    (payload : ExactListInferenceConcreteProjection outer concrete
      surfaceArguments observedTypes groundPayload coreArguments) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) surfaceArguments)
      (.nominal constructor.sourceType symbolicTypeArguments
        symbolicConstArguments)
      (.nominal constructor.sourceType resolved.typeArguments
        resolved.constArguments)
      (.enumValue resolved.coreType constructor.variant coreArguments) :=
  ⟨evidence.nominal.typeGrounds,
    .variantCallInferred (contexts.selectsVariantConstructor evidence.selected)
      evidence.notIntrinsic evidence.implicitArguments evidence.generic evidence.determined
      (payload.symbolicLowerings evidence.typeMatches)
      (evidence.nominal.instantiates contexts)⟩

theorem ExactInferenceConcreteProjection.variantNongeneric
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : VariantNongenericEvidence outer concrete symbolic path constructor
      inner resolved)
    (payload : SurfaceElaboration.SymbolicExprsCheck concrete
      (inner.composeGround outer) surfaceArguments constructor.payload
      coreArguments) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) surfaceArguments) (.nominal constructor.sourceType [] [])
      (.nominal constructor.sourceType resolved.typeArguments
        resolved.constArguments)
      (.enumValue resolved.coreType constructor.variant coreArguments) :=
  ⟨evidence.nominal.typeGrounds,
    .variantCallNongeneric (contexts.selectsVariantConstructor evidence.selected)
      evidence.notIntrinsic evidence.implicitArguments evidence.nongeneric
      (evidence.nominal.instantiates contexts) payload⟩

theorem ExactInferenceConcreteProjection.directCall
    (returnGrounds : returnType.instantiate outer = some resolved.returnType)
    (arguments : SurfaceElaboration.ExprsCheck concrete surfaceArguments
      resolved.parameterTypes coreArguments)
    (resolves : SurfaceElaboration.ResolvesDirectCall concrete path
      resolved.parameterTypes scheme resolved)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) surfaceArguments) returnType resolved.returnType
      (.call resolved.function coreArguments) :=
  ⟨returnGrounds, .directCall arguments resolves notIntrinsic rfl⟩

theorem ExactInferenceConcreteProjection.directCallInferred
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : DirectCallInferenceEvidence outer concrete symbolic path
      observedTypes returnType scheme inner resolved)
    (arguments : ExactListInferenceConcreteProjection outer concrete
      surfaceArguments observedTypes resolved.parameterTypes coreArguments) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) surfaceArguments) returnType resolved.returnType
      (.call resolved.function coreArguments) :=
  .directCall evidence.returnGrounds arguments.checks
    (evidence.resolvesDirectCall contexts) evidence.notIntrinsic

theorem ExactInferenceConcreteProjection.directCallExplicit
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : DirectCallExplicitEvidence outer concrete symbolic path
      parameterTypes returnType scheme inner resolved)
    (arguments : SurfaceElaboration.ExprsCheck concrete surfaceArguments
      resolved.parameterTypes coreArguments) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) surfaceArguments) returnType resolved.returnType
      (.call resolved.function coreArguments) :=
  .directCall evidence.returnGrounds arguments
    (evidence.resolvesDirectCall contexts) evidence.notIntrinsic

theorem ExactInferenceConcreteProjection.directCallNongeneric
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : DirectCallNongenericEvidence outer concrete symbolic path
      scheme resolved)
    (arguments : SurfaceElaboration.ExprsCheck concrete surfaceArguments
      resolved.parameterTypes coreArguments) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) surfaceArguments) scheme.returnType resolved.returnType
      (.call resolved.function coreArguments) :=
  .directCall evidence.returnGrounds arguments
    (evidence.resolvesDirectCall contexts) evidence.notIntrinsic

theorem ExactInferenceConcreteProjection.associatedCallInferred
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : AssociatedCallInferenceEvidence outer concrete symbolic path
      ownerPath name receiverType sourceParameterTypes observedTypes
      groundArgumentTypes returnType scheme inner resolved)
    (arguments : ExactListInferenceConcreteProjection outer concrete
      surfaceArguments observedTypes groundArgumentTypes coreArguments) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) surfaceArguments) returnType resolved.returnType
      (.call resolved.function coreArguments) :=
  ⟨evidence.returnGrounds,
    evidence.concreteLowering contexts arguments.checks⟩

theorem ExactInferenceConcreteProjection.associatedCallContextual
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : AssociatedCallContextualEvidence outer concrete symbolic path
      ownerPath name receiverType sourceParameterTypes expectedArgumentTypes
      groundArgumentTypes returnType scheme inner resolved)
    (arguments : SurfaceElaboration.ExprsCheck concrete surfaceArguments
      groundArgumentTypes coreArguments) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) surfaceArguments) returnType resolved.returnType
      (.call resolved.function coreArguments) :=
  ⟨evidence.returnGrounds,
    evidence.concreteLowering contexts arguments⟩

theorem ExactInferenceConcreteProjection.methodCallInferred
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : MethodCallInferenceEvidence outer concrete symbolic receiverType
      name observedTypes returnType scheme inner resolved)
    (receiver : ExactInferenceConcreteProjection outer concrete surfaceReceiver
      sourceReceiver sourceGround sourceCore)
    (memberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      sourceGround sourceCore resolved.receiverType receiverCore)
    (arguments : ExactListInferenceConcreteProjection outer concrete
      surfaceArguments observedTypes resolved.argumentTypes coreArguments)
    (receiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization resolved.receiverMode resolved.receiverType
      receiverCore receiverArgumentCore) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.member surfaceReceiver name) surfaceArguments) returnType
      resolved.returnType
      (.call resolved.function (receiverArgumentCore :: coreArguments)) :=
  ⟨evidence.returnGrounds,
    evidence.concreteLowering contexts receiver.typeGrounds receiver.lowers
      memberLowers arguments.checks receiverArgument⟩

theorem ExactInferenceConcreteProjection.methodCallContextual
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (evidence : MethodCallContextualEvidence outer concrete symbolic receiverType
      name expectedArgumentTypes returnType scheme inner resolved)
    (receiver : ExactInferenceConcreteProjection outer concrete surfaceReceiver
      sourceReceiver sourceGround sourceCore)
    (memberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      sourceGround sourceCore resolved.receiverType receiverCore)
    (arguments : SurfaceElaboration.ExprsCheck concrete surfaceArguments
      resolved.argumentTypes coreArguments)
    (receiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization resolved.receiverMode resolved.receiverType
      receiverCore receiverArgumentCore) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.member surfaceReceiver name) surfaceArguments) returnType
      resolved.returnType
      (.call resolved.function (receiverArgumentCore :: coreArguments)) :=
  ⟨evidence.returnGrounds,
    evidence.concreteLowering contexts receiver.lowers memberLowers arguments
      receiverArgument⟩

theorem ExactInferenceConcreteProjection.assign
    (place : ExactPlaceConcreteProjection outer concrete surfacePlace
      placeType groundPlace corePlace)
    (value : ExactCheckingConcreteProjection outer concrete surfaceValue
      placeType groundPlace coreValue)
    (coreGrounds : groundPlace.toCore concrete.monomorphization =
      some corePlaceType)
    (typed : SymbolicAssignOpHasType op placeType) :
    ExactInferenceConcreteProjection outer concrete
      (.assign op surfacePlace surfaceValue) .unit .unit
      (.assign (SurfaceElaboration.lowerAssignOp op) corePlace coreValue) :=
  ⟨rfl, .assign place.lowers value.checks coreGrounds
    (typed.specializes place.typeGrounds coreGrounds)⟩

theorem ExactCheckingConcreteProjection.array
    (elements : SurfaceElaboration.ExprsCheck concrete surfaceElements
      (List.replicate surfaceElements.length groundElement) coreElements)
    (elementGrounds : elementType.instantiate outer = some groundElement)
    (elementCore : groundElement.toCore concrete.monomorphization =
      some coreElementType) :
    ExactCheckingConcreteProjection outer concrete (.array surfaceElements)
      (.array elementType (.literal surfaceElements.length))
      (.array groundElement surfaceElements.length)
      (.array coreElementType coreElements) :=
  ⟨by simp [Static.Ty.instantiate, Static.Const.instantiate, elementGrounds],
    .array elements elementCore⟩

theorem SymbolicBodyContext.Specializes.scalarCastCheck
    {outer : Static.Substitution}
    {groundEnclosingReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (concreteInferred : SurfaceElaboration.ExprLowers concrete surfaceExpression
      (.scalar sourceType) coreExpression)
    (notContextualLiteral : ¬ SurfaceElaboration.ContextualScalarLiteralApplies
      symbolic.globals.target surfaceExpression targetType)
    (different : sourceType ≠ targetType)
    (conversion : Typing.ScalarCast sourceType targetType) :
    SurfaceElaboration.ExprChecks concrete surfaceExpression
      (.scalar targetType) (.cast targetType coreExpression) :=
  .scalarCast concreteInferred (by
    rw [contexts.target]
    exact notContextualLiteral) different conversion

theorem ExactCheckingConcreteProjection.scalarCast
    {symbolic : SymbolicBodyContext}
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (concreteInferred : SurfaceElaboration.ExprLowers concrete surfaceExpression
      (.scalar sourceType) coreExpression)
    (notContextualLiteral : ¬ SurfaceElaboration.ContextualScalarLiteralApplies
      symbolic.globals.target surfaceExpression targetType)
    (different : sourceType ≠ targetType)
    (conversion : Typing.ScalarCast sourceType targetType) :
    ExactCheckingConcreteProjection outer concrete surfaceExpression
      (.scalar targetType) (.scalar targetType) (.cast targetType coreExpression) :=
  ⟨rfl, contexts.scalarCastCheck concreteInferred notContextualLiteral different
    conversion⟩

theorem ExactCheckingConcreteProjection.arrayToSlice
    (concreteInferred : SurfaceElaboration.ExprLowers concrete surfaceExpression
      (.array groundElement groundLength) coreArray)
    (elementGrounds : elementType.instantiate outer = some groundElement)
    (elementCore : groundElement.toCore concrete.monomorphization =
      some coreElementType) :
    ExactCheckingConcreteProjection outer concrete surfaceExpression
      (.slice elementType) (.slice groundElement)
      (.arrayToSlice coreElementType coreArray) :=
  ⟨by simp [Static.Ty.instantiate, elementGrounds],
    .arrayToSlice concreteInferred elementCore⟩

theorem ExactCheckingConcreteProjection.structValue
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (selected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path constructor)
    (expected : expectedType = .nominal constructor.sourceType
      symbolicTypeArguments symbolicConstArguments)
    (arguments : Static.SymbolicArgumentsBound inner
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer
      symbolicConstArguments = some groundConstArguments)
    (pathArguments : SymbolicPathArgumentsCompatible symbolic.globals path
      constructor.genericParameters inner)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer inner
      constructor.requirements)
    (artifact : NominalArtifactDemand concrete constructor.declaration
      constructor.sourceType .structure groundTypeArguments groundConstArguments
      resolved)
    (concreteFields : SurfaceElaboration.StructSchemeFieldsCheck concrete
      (inner.composeGround outer) constructor.fields surfaceFields coreFields) :
    ExactCheckingConcreteProjection outer concrete
      (.structValue path surfaceFields) expectedType
      (.nominal constructor.sourceType resolved.typeArguments
        resolved.constArguments)
      (.structValue resolved.coreType coreFields) := by
  have parametersGround := arguments.parametersGround typeArgumentsGround
    constArgumentsGround
  have concretePath := pathArguments.specializes contexts parametersGround
  have instantiated := artifact.instantiates contexts arguments
    typeArgumentsGround constArgumentsGround requirements
  exact ⟨by
    rw [expected]
    simp [Static.Ty.instantiate, typeArgumentsGround, constArgumentsGround,
      artifact.typeArguments, artifact.constArguments],
    .structValue (contexts.selectsStructConstructor selected) concretePath
      instantiated rfl concreteFields⟩

theorem ExactCheckingConcreteProjection.variantCall
    {outer : Static.Substitution} {groundReturn : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    (contexts : symbolic.Specializes outer groundReturn concrete)
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
    (expected : expectedType = .nominal constructor.sourceType
      symbolicTypeArguments symbolicConstArguments)
    (arguments : Static.SymbolicArgumentsBound inner
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (typeArgumentsGround : Static.instantiateTypes outer symbolicTypeArguments =
      some groundTypeArguments)
    (constArgumentsGround : Static.instantiateConstants outer
      symbolicConstArguments = some groundConstArguments)
    (pathArguments : SymbolicPathArgumentsCompatible symbolic.globals path
      constructor.genericParameters inner)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer inner
      constructor.requirements)
    (artifact : NominalArtifactDemand concrete constructor.nominalDeclaration
      constructor.sourceType .enumeration groundTypeArguments groundConstArguments
      resolved)
    (concretePayload : SurfaceElaboration.SymbolicExprsCheck concrete
      (inner.composeGround outer) surfaceArguments constructor.payload
      coreArguments) :
    ExactCheckingConcreteProjection outer concrete
      (.call (.path path) surfaceArguments) expectedType
      (.nominal constructor.sourceType resolved.typeArguments
        resolved.constArguments)
      (.enumValue resolved.coreType constructor.variant coreArguments) := by
  have parametersGround := arguments.parametersGround typeArgumentsGround
    constArgumentsGround
  have concretePath := pathArguments.specializes contexts parametersGround
  have instantiated := artifact.instantiates contexts arguments
    typeArgumentsGround constArgumentsGround requirements
  exact ⟨by
    rw [expected]
    simp [Static.Ty.instantiate, typeArgumentsGround, constArgumentsGround,
      artifact.typeArguments, artifact.constArguments],
    .variantCall (contexts.selectsVariantConstructor selected) notIntrinsic
      concretePath instantiated rfl concretePayload⟩

theorem concreteSubstitutedChecksCons
    (substituted : originalHead.substitute inner = some expectedHead)
    (head : ExactCheckingConcreteProjection outer concrete surfaceHead
      expectedHead groundHead coreHead)
    (tail : SurfaceElaboration.SymbolicExprsCheck concrete
      (inner.composeGround outer) surfaceTail originalTail coreTail) :
    SurfaceElaboration.SymbolicExprsCheck concrete (inner.composeGround outer)
      (surfaceHead :: surfaceTail) (originalHead :: originalTail)
      (coreHead :: coreTail) :=
  .cons (Static.Ty.substitute_then_instantiate substituted head.typeGrounds)
    head.checks tail

theorem concreteExprsCheckCons
    (head : ExactCheckingConcreteProjection outer concrete surfaceHead
      symbolicHead groundHead coreHead)
    (tail : SurfaceElaboration.ExprsCheck concrete surfaceTail groundTail
      coreTail) :
    SurfaceElaboration.ExprsCheck concrete (surfaceHead :: surfaceTail)
      (groundHead :: groundTail) (coreHead :: coreTail) :=
  .cons head.checks tail

theorem concreteMatchArmsCons
    (pattern : PatternDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts next surfacePattern symbolicScrutinee groundScrutinee
      corePattern symbolicBindings concreteBindings patternFinal)
    (body : ExactCheckingConcreteProjection outer
      (concrete.bindLocals concreteBindings) surfaceBody symbolicResult
      groundResult coreBody)
    (tail : SurfaceElaboration.MatchArmsLower concrete groundScrutinee
      groundResult surfaceTail coreTail) :
    SurfaceElaboration.MatchArmsLower concrete groundScrutinee groundResult
      ((surfacePattern, surfaceBody) :: surfaceTail)
      ((corePattern, coreBody) :: coreTail) :=
  .cons pattern.concretePattern body.checks tail

theorem concreteMatchArmsInferCons
    (pattern : PatternDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts next surfacePattern symbolicScrutinee groundScrutinee
      corePattern symbolicBindings concreteBindings patternFinal)
    (body : ExactInferenceConcreteProjection outer
      (concrete.bindLocals concreteBindings) surfaceBody symbolicResult
      groundResult coreBody)
    (tail : SurfaceElaboration.MatchArmsLower concrete groundScrutinee
      groundResult surfaceTail coreTail) :
    SurfaceElaboration.MatchArmsInfer concrete groundScrutinee groundResult
      ((surfacePattern, surfaceBody) :: surfaceTail)
      ((corePattern, coreBody) :: coreTail) :=
  .cons pattern.concretePattern body.lowers tail

theorem concreteStructFieldsCheckCons
    (removed : SurfaceElaboration.RemovesNamedField field.name surfaceFields
      surfaceValue remainder)
    (substituted : field.type.substitute inner = some expectedType)
    (value : ExactCheckingConcreteProjection outer concrete surfaceValue
      expectedType groundType coreValue)
    (tail : SurfaceElaboration.StructSchemeFieldsCheck concrete
      (inner.composeGround outer) fieldTail remainder coreTail) :
    SurfaceElaboration.StructSchemeFieldsCheck concrete
      (inner.composeGround outer) (field :: fieldTail) surfaceFields
      (coreValue :: coreTail) :=
  .cons removed
    (Static.Ty.substitute_then_instantiate substituted value.typeGrounds)
    value.checks tail

theorem concreteStructFieldsInferCons
    (removed : SurfaceElaboration.RemovesNamedField field.name surfaceFields
      surfaceValue remainder)
    (value : ExactInferenceConcreteProjection outer concrete surfaceValue
      actualType groundType coreValue)
    (matched : Static.TySymbolicallyMatches inner field.type actualType)
    (tail : SurfaceElaboration.StructSchemeFieldsInfer concrete
      (inner.composeGround outer) fieldTail remainder coreTail) :
    SurfaceElaboration.StructSchemeFieldsInfer concrete
      (inner.composeGround outer) (field :: fieldTail) surfaceFields
      (coreValue :: coreTail) :=
  .cons removed value.lowers
    (matched.composeGround (Static.Ty.matchesOfInstantiate value.typeGrounds)) tail

theorem ExactPlaceConcreteProjection.field
    (base : ExactPlaceConcreteProjection outer concrete surfaceBase receiverType
      groundReceiver coreBase)
    (concreteSelected : SurfaceElaboration.SelectsField concrete groundReceiver
      name entry)
    (fieldGrounds : fieldType.instantiate outer = some entry.type) :
    ExactPlaceConcreteProjection outer concrete (.member surfaceBase name)
      fieldType entry.type (.field coreBase entry.field) :=
  ⟨fieldGrounds, .field base.lowers concreteSelected⟩

theorem ExactPlaceConcreteProjection.indexArray
    (base : ExactPlaceConcreteProjection outer concrete surfaceBase
      (.array elementType length) (.array groundElement groundLength) coreBase)
    (elementGrounds : elementType.instantiate outer = some groundElement)
    (index : ExactInferenceConcreteProjection outer concrete surfaceIndex
      indexType groundIndex coreIndex)
    (integer : SymbolicIntegerType indexType) :
    ExactPlaceConcreteProjection outer concrete (.index surfaceBase surfaceIndex)
      elementType groundElement (.index coreBase coreIndex) := by
  obtain ⟨coreIndexType, indexCore, coreInteger⟩ :=
    integer.specializes index.typeGrounds
  exact ⟨elementGrounds,
    .indexArray base.lowers index.lowers indexCore coreInteger⟩

theorem ExactPlaceConcreteProjection.indexSlice
    (base : ExactPlaceConcreteProjection outer concrete surfaceBase
      (.slice elementType) (.slice groundElement) coreBase)
    (elementGrounds : elementType.instantiate outer = some groundElement)
    (index : ExactInferenceConcreteProjection outer concrete surfaceIndex
      indexType groundIndex coreIndex)
    (integer : SymbolicIntegerType indexType) :
    ExactPlaceConcreteProjection outer concrete (.index surfaceBase surfaceIndex)
      elementType groundElement (.index coreBase coreIndex) := by
  obtain ⟨coreIndexType, indexCore, coreInteger⟩ :=
    integer.specializes index.typeGrounds
  exact ⟨elementGrounds,
    .indexSlice base.lowers index.lowers indexCore coreInteger⟩

local macro "deriveExactConcreteProjection" outerSubstitution:ident
    groundReturn:ident recursor:term : tactic =>
  `(tactic|
    (apply $recursor
        (outer := $outerSubstitution) (groundEnclosingReturn := $groundReturn)
        (motive_1 := fun _ concrete _ surface symbolicType groundType core _ =>
          ExactInferenceConcreteProjection $outerSubstitution concrete surface
            symbolicType groundType core)
        (motive_2 := fun _ concrete _ surfaces symbolicTypes groundTypes cores _ =>
          ExactListInferenceConcreteProjection $outerSubstitution concrete
            surfaces symbolicTypes groundTypes cores)
        (motive_3 := fun _ concrete _ surface symbolicType groundType core _ =>
          ExactCheckingConcreteProjection $outerSubstitution concrete surface
            symbolicType groundType core)
        (motive_4 := fun _ concrete _ surfaces _ groundTypes cores _ =>
          SurfaceElaboration.ExprsCheck concrete surfaces groundTypes cores)
        (motive_5 := fun _ concrete _ inner surfaces originalTypes cores _ =>
          SurfaceElaboration.SymbolicExprsCheck concrete
            (inner.composeGround $outerSubstitution) surfaces originalTypes cores)
        (motive_6 := fun _ concrete _ inner fields surfaceFields cores _ =>
          SurfaceElaboration.StructSchemeFieldsCheck concrete
            (inner.composeGround $outerSubstitution) fields surfaceFields cores)
        (motive_7 := fun _ concrete _ inner fields surfaceFields cores _ =>
          SurfaceElaboration.StructSchemeFieldsInfer concrete
            (inner.composeGround $outerSubstitution) fields surfaceFields cores)
        (motive_8 := fun _ concrete _ surface symbolicType groundType core _ =>
          ExactPlaceConcreteProjection $outerSubstitution concrete surface
            symbolicType groundType core)
        (motive_9 := fun _ concrete _ _ _ _ groundScrutinee groundResult
            surfaceArms coreArms _ =>
          SurfaceElaboration.MatchArmsLower concrete groundScrutinee groundResult
            surfaceArms coreArms)
        (motive_10 := fun _ concrete _ _ _ _ groundScrutinee groundResult
            surfaceArms coreArms _ =>
          SurfaceElaboration.MatchArmsInfer concrete groundScrutinee groundResult
            surfaceArms coreArms) <;>
      intros <;>
      (first
        | solve_by_elim (maxDepth := 20) [
            ExactInferenceConcreteProjection.associatedCallInferred,
            ExactInferenceConcreteProjection.associatedCallContextual,
            ExactInferenceConcreteProjection.literal,
            ExactInferenceConcreteProjection.signedMinimumLiteral,
            ExactInferenceConcreteProjection.array,
            ExactInferenceConcreteProjection.unaryScalar,
            ExactInferenceConcreteProjection.binaryExact,
            ExactInferenceConcreteProjection.binaryNullPointerRight,
            ExactInferenceConcreteProjection.binaryNullPointerLeft,
            ExactInferenceConcreteProjection.binaryRightCast,
            ExactInferenceConcreteProjection.binaryLeftCast,
            ExactInferenceConcreteProjection.printI32,
            ExactInferenceConcreteProjection.assert,
            ExactInferenceConcreteProjection.i32ArrayDataPtr,
            ExactInferenceConcreteProjection.indexArray,
            ExactInferenceConcreteProjection.indexSlice,
            ExactInferenceConcreteProjection.field,
            ExactInferenceConcreteProjection.matchValue,
            ExactInferenceConcreteProjection.structExplicit,
            ExactInferenceConcreteProjection.structInferred,
            ExactInferenceConcreteProjection.structNongeneric,
            ExactInferenceConcreteProjection.variantExplicit,
            ExactInferenceConcreteProjection.variantInferred,
            ExactInferenceConcreteProjection.variantNongeneric,
            ExactInferenceConcreteProjection.directCall,
            ExactInferenceConcreteProjection.directCallInferred,
            ExactInferenceConcreteProjection.directCallExplicit,
            ExactInferenceConcreteProjection.directCallNongeneric,
            ExactInferenceConcreteProjection.methodCallInferred,
            ExactInferenceConcreteProjection.methodCallContextual,
            ExactInferenceConcreteProjection.assign,
            ExactListInferenceConcreteProjection.cons,
            ExactCheckingConcreteProjection.literal,
            ExactCheckingConcreteProjection.signedMinimumLiteral,
            ExactCheckingConcreteProjection.unaryLiteral,
            ExactCheckingConcreteProjection.array,
            ExactCheckingConcreteProjection.scalarCast,
            ExactCheckingConcreteProjection.arrayToSlice,
            ExactCheckingConcreteProjection.structValue,
            ExactCheckingConcreteProjection.variantCall,
            concreteExprsCheckCons,
            concreteMatchArmsCons,
            concreteMatchArmsInferCons,
            concreteSubstitutedChecksCons,
            concreteStructFieldsCheckCons,
            concreteStructFieldsInferCons,
            ExactPlaceConcreteProjection.field,
            ExactPlaceConcreteProjection.indexArray,
            ExactPlaceConcreteProjection.indexSlice]
        | refine { typeGrounds := ?_, lowers := ?_ }
        | refine { typeGrounds := ?_, checks := ?_ }
        | refine { lowerings := ?_, checks := ?_ }
        | skip) <;>
      (try simp_all [Static.Ty.instantiate, Static.Const.instantiate,
        Static.GroundTy.toCore, SymbolicBodyContext.Specializes.target]) <;>
      first
      | assumption
      | solve_by_elim (maxDepth := 3) [
        Eq.refl,
        ExactInferenceConcreteProjection.typeGrounds,
        ExactInferenceConcreteProjection.lowers,
        ExactCheckingConcreteProjection.typeGrounds,
        ExactCheckingConcreteProjection.checks,
        ExactListInferenceConcreteProjection.typeGrounds,
        ExactListInferenceConcreteProjection.lowerings,
        ExactListInferenceConcreteProjection.checks,
        ExactPlaceConcreteProjection.typeGrounds,
        ExactPlaceConcreteProjection.lowers,
        ExactInferenceConcreteProjection.literal,
        ExactInferenceConcreteProjection.signedMinimumLiteral,
        ExactInferenceConcreteProjection.array,
        ExactInferenceConcreteProjection.unaryScalar,
        ExactInferenceConcreteProjection.binaryExact,
        ExactInferenceConcreteProjection.binaryNullPointerRight,
        ExactInferenceConcreteProjection.binaryNullPointerLeft,
        ExactInferenceConcreteProjection.binaryRightCast,
        ExactInferenceConcreteProjection.binaryLeftCast,
        ExactListInferenceConcreteProjection.cons,
        ExactCheckingConcreteProjection.literal,
        ExactCheckingConcreteProjection.signedMinimumLiteral,
        ExactCheckingConcreteProjection.unaryLiteral,
        SymbolicBodyContext.Specializes.scalarCastCheck,
        SymbolicBodyContext.Specializes.target,
        Static.GroundTy.toTy_instantiate,
        Static.Ty.substitute_then_instantiate,
        Static.Ty.matchesOfInstantiate,
        Static.TySymbolicallyMatches.composeGround,
        DirectCallInferenceEvidence.returnGrounds,
        DirectCallInferenceEvidence.notIntrinsic,
        DirectCallInferenceEvidence.resolvesDirectCall,
        DirectCallExplicitEvidence.returnGrounds,
        DirectCallExplicitEvidence.notIntrinsic,
        DirectCallExplicitEvidence.resolvesDirectCall,
        DirectCallNongenericEvidence.returnGrounds,
        DirectCallNongenericEvidence.notIntrinsic,
        DirectCallNongenericEvidence.resolvesDirectCall,
        ExactInferenceConcreteProjection.associatedCallInferred,
        ExactInferenceConcreteProjection.associatedCallContextual,
        MethodCallInferenceEvidence.returnGrounds,
        MethodCallInferenceEvidence.concreteLowering,
        MethodCallContextualEvidence.returnGrounds,
        MethodCallContextualEvidence.concreteLowering,
        SymbolicIntegerType.specializes,
        SymbolicAssignOpHasType.specializes,
        SurfaceElaboration.ExprLowers.literal,
        SurfaceElaboration.ExprLowers.signedMinimumLiteral,
        SurfaceElaboration.ExprLowers.local,
        SurfaceElaboration.ExprLowers.selfValue,
        SurfaceElaboration.ExprLowers.constant,
        SurfaceElaboration.ExprLowers.array,
        SurfaceElaboration.ExprLowers.unary,
        SurfaceElaboration.ExprLowers.binary,
        SurfaceElaboration.ExprLowers.binaryRightCast,
        SurfaceElaboration.ExprLowers.binaryLeftCast,
        SurfaceElaboration.ExprLowers.assign,
        SurfaceElaboration.ExprLowers.printI32,
        SurfaceElaboration.ExprLowers.assert,
        SurfaceElaboration.ExprLowers.i32ArrayDataPtr,
        SurfaceElaboration.ExprLowers.directCall,
        SurfaceElaboration.ExprLowers.indexArray,
        SurfaceElaboration.ExprLowers.indexSlice,
        SurfaceElaboration.ExprLowers.field,
        SurfaceElaboration.ExprLowers.matchValue,
        SurfaceElaboration.ExprsLower.nil,
        SurfaceElaboration.ExprsLower.cons,
        SurfaceElaboration.ExprChecks.exact,
        SurfaceElaboration.ExprChecks.literal,
        SurfaceElaboration.ExprChecks.signedMinimumLiteral,
        SurfaceElaboration.ExprChecks.unaryLiteral,
        SurfaceElaboration.ExprChecks.array,
        SurfaceElaboration.ExprChecks.scalarCast,
        SurfaceElaboration.ExprChecks.arrayToSlice,
        SurfaceElaboration.ExprChecks.structValue,
        SurfaceElaboration.ExprChecks.variantCall,
        SurfaceElaboration.ExprsCheck.nil,
        SurfaceElaboration.ExprsCheck.cons,
        SurfaceElaboration.SymbolicExprsCheck.nil,
        SurfaceElaboration.SymbolicExprsCheck.cons,
        SurfaceElaboration.StructSchemeFieldsCheck.nil,
        SurfaceElaboration.StructSchemeFieldsCheck.cons,
        SurfaceElaboration.StructSchemeFieldsInfer.nil,
        SurfaceElaboration.StructSchemeFieldsInfer.cons,
        SurfaceElaboration.PlaceLowers.local,
        SurfaceElaboration.PlaceLowers.selfValue,
        SurfaceElaboration.PlaceLowers.field,
        SurfaceElaboration.PlaceLowers.indexArray,
        SurfaceElaboration.PlaceLowers.indexSlice,
        PatternDerivationSpecializes.concretePattern,
        SurfaceElaboration.MatchArmsLower.nil,
        SurfaceElaboration.MatchArmsLower.cons,
        SurfaceElaboration.MatchArmsInfer.cons]
      | skip))

theorem ExprInferenceDerivationSpecializes.concreteProjection
    (specialized : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface symbolicType
      groundType coreExpression) :
    ExactInferenceConcreteProjection outer concrete surface symbolicType
      groundType coreExpression := by
  deriveExactConcreteProjection outer groundEnclosingReturn
    ExprInferenceDerivationSpecializes.rec

theorem ExprInferenceDerivationSpecializes.concreteInference
    (specialized : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface symbolicType
      groundType coreExpression) :
    symbolicType.instantiate outer = some groundType ∧
      SurfaceElaboration.ExprLowers concrete surface groundType coreExpression :=
  ⟨specialized.concreteProjection.typeGrounds,
    specialized.concreteProjection.lowers⟩

theorem ExprListInferenceDerivationSpecializes.concreteProjection
    (specialized : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
      groundTypes coreExpressions) :
    ExactListInferenceConcreteProjection outer concrete surfaces symbolicTypes
      groundTypes coreExpressions := by
  deriveExactConcreteProjection outer groundEnclosingReturn
    ExprListInferenceDerivationSpecializes.rec

theorem ExprListInferenceDerivationSpecializes.concreteLowerings
    (specialized : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
      groundTypes coreExpressions) :
    SurfaceElaboration.ExprsLower concrete surfaces groundTypes coreExpressions :=
  specialized.concreteProjection.lowerings

theorem ExprListInferenceDerivationSpecializes.concreteChecks
    (specialized : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
      groundTypes coreExpressions) :
    SurfaceElaboration.ExprsCheck concrete surfaces groundTypes coreExpressions :=
  specialized.concreteProjection.checks

theorem ExprCheckingDerivationSpecializes.concreteProjection
    (specialized : ExprCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface symbolicType
      groundType coreExpression) :
    ExactCheckingConcreteProjection outer concrete surface symbolicType
      groundType coreExpression := by
  deriveExactConcreteProjection outer groundEnclosingReturn
    ExprCheckingDerivationSpecializes.rec

theorem ExprCheckingDerivationSpecializes.concreteCheck
    (specialized : ExprCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface symbolicType
      groundType coreExpression) :
    symbolicType.instantiate outer = some groundType ∧
      SurfaceElaboration.ExprChecks concrete surface groundType coreExpression :=
  ⟨specialized.concreteProjection.typeGrounds,
    specialized.concreteProjection.checks⟩

theorem ExprListCheckingDerivationSpecializes.concreteChecks
    (specialized : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
      groundTypes coreExpressions) :
    SurfaceElaboration.ExprsCheck concrete surfaces groundTypes coreExpressions := by
  deriveExactConcreteProjection outer groundEnclosingReturn
    ExprListCheckingDerivationSpecializes.rec

theorem ExprListSubstitutedCheckingDerivationSpecializes.concreteChecks
    (specialized : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner surfaces
      originalTypes coreExpressions) :
    SurfaceElaboration.SymbolicExprsCheck concrete (inner.composeGround outer)
      surfaces originalTypes coreExpressions := by
  deriveExactConcreteProjection outer groundEnclosingReturn
    ExprListSubstitutedCheckingDerivationSpecializes.rec

theorem StructFieldsCheckingDerivationSpecializes.concreteFields
    (specialized : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner fields surfaceFields
      coreFields) :
    SurfaceElaboration.StructSchemeFieldsCheck concrete
      (inner.composeGround outer) fields surfaceFields coreFields := by
  deriveExactConcreteProjection outer groundEnclosingReturn
    StructFieldsCheckingDerivationSpecializes.rec

theorem StructFieldsInferenceDerivationSpecializes.concreteFields
    (specialized : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner fields surfaceFields
      coreFields) :
    SurfaceElaboration.StructSchemeFieldsInfer concrete
      (inner.composeGround outer) fields surfaceFields coreFields := by
  deriveExactConcreteProjection outer groundEnclosingReturn
    StructFieldsInferenceDerivationSpecializes.rec

theorem PlaceDerivationSpecializes.concreteProjection
    (specialized : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surface symbolicType groundType corePlace) :
    ExactPlaceConcreteProjection outer concrete surface symbolicType groundType
      corePlace := by
  deriveExactConcreteProjection outer groundEnclosingReturn
    PlaceDerivationSpecializes.rec

theorem PlaceDerivationSpecializes.concretePlace
    (specialized : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surface symbolicType groundType corePlace) :
    symbolicType.instantiate outer = some groundType ∧
      SurfaceElaboration.PlaceLowers concrete surface groundType corePlace :=
  ⟨specialized.concreteProjection.typeGrounds,
    specialized.concreteProjection.lowers⟩

theorem MatchArmsDerivationSpecializes.concreteArms
    (specialized : MatchArmsDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next symbolicScrutinee symbolicResult
      groundScrutinee groundResult surfaceArms coreArms) :
    SurfaceElaboration.MatchArmsLower concrete groundScrutinee groundResult
      surfaceArms coreArms := by
  deriveExactConcreteProjection outer groundEnclosingReturn
    MatchArmsDerivationSpecializes.rec

theorem MatchArmsInferenceDerivationSpecializes.concreteArms
    (specialized : MatchArmsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts next symbolicScrutinee
      symbolicResult groundScrutinee groundResult surfaceArms coreArms) :
    SurfaceElaboration.MatchArmsInfer concrete groundScrutinee groundResult
      surfaceArms coreArms := by
  deriveExactConcreteProjection outer groundEnclosingReturn
    MatchArmsInferenceDerivationSpecializes.rec

theorem ExprInferenceDerivationSpecializes.asChecking
    (specialized : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface symbolicType
      groundType coreExpression) :
    ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surface symbolicType groundType coreExpression :=
  .exact specialized specialized.symbolicInference
    specialized.concreteInference.1 specialized.concreteInference.2

theorem ExprListInferenceDerivationSpecializes.asChecking
    (specialized : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
      groundTypes coreExpressions) :
    ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surfaces symbolicTypes groundTypes coreExpressions := by
  induction surfaces generalizing symbolicTypes groundTypes coreExpressions with
  | nil =>
      cases specialized
      exact .nil
  | cons surfaceHead surfaceTail induction =>
      cases specialized with
      | cons head tail => exact .cons head.asChecking (induction tail)

theorem ExprInferenceDerivationSpecializes.scalarCast
    (specialized : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface
      (.scalar sourceType) (.scalar sourceType) coreExpression)
    (notContextualLiteral : ¬ SurfaceElaboration.ContextualScalarLiteralApplies
      symbolic.globals.target surface targetType)
    (different : sourceType ≠ targetType)
    (conversion : Typing.ScalarCast sourceType targetType) :
    ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surface (.scalar targetType) (.scalar targetType)
      (.cast targetType coreExpression) :=
  .scalarCast specialized specialized.symbolicInference
    specialized.concreteInference.2 notContextualLiteral different conversion

theorem ExprInferenceDerivationSpecializes.arrayToSlice
    (specialized : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface
      (.array elementType length) (.array groundElement groundLength) coreArray)
    (elementGrounds : elementType.instantiate outer = some groundElement)
    (elementCore : groundElement.toCore concrete.monomorphization =
      some coreElementType) :
    ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surface (.slice elementType) (.slice groundElement)
      (.arrayToSlice coreElementType coreArray) :=
  .arrayToSlice specialized specialized.symbolicInference
    specialized.concreteInference.2 elementGrounds elementCore

theorem SymbolicPlaceHasType.fieldSpecializes
    (base : PlaceSpecializes substitution concrete surfaceBase receiverType)
    (receiverGrounds : receiverType.instantiate substitution = some groundReceiver)
    (selected : SurfaceElaboration.SelectsField concrete groundReceiver name entry)
    (fieldGrounds : fieldType.instantiate substitution = some entry.type) :
    PlaceSpecializes substitution concrete (.member surfaceBase name) fieldType := by
  cases base with
  | intro actualReceiver coreBase actualGrounds baseLowers =>
      rw [receiverGrounds] at actualGrounds
      have receiverEquality := Option.some.inj actualGrounds
      subst actualReceiver
      exact .intro entry.type (.field coreBase entry.field) fieldGrounds
        (.field baseLowers selected)

inductive SymbolicRangeBoundChecks (context : SymbolicBodyContext) :
    Surface.RangeBound → Prop where
  | integer
      (checked : SymbolicExprChecks context (.literal (.integer text))
        (.scalar (.signed .i32))) :
      SymbolicRangeBoundChecks context (.integer text)
  | postfix
      (formed : Surface.RangeBoundPostfix surfaceExpression)
      (checked : SymbolicExprChecks context surfaceExpression
        (.scalar (.signed .i32))) :
      SymbolicRangeBoundChecks context (.postfix surfaceExpression)

inductive SymbolicRangeChecks (context : SymbolicBodyContext) :
    Surface.RangeKind → Option Surface.RangeBound →
      Option Surface.RangeBound → Prop where
  | full : SymbolicRangeChecks context .full none none
  | from (start : SymbolicRangeBoundChecks context surfaceStart) :
      SymbolicRangeChecks context .from (some surfaceStart) none
  | toExclusive (stop : SymbolicRangeBoundChecks context surfaceStop) :
      SymbolicRangeChecks context .toExclusive none (some surfaceStop)
  | toInclusive (stop : SymbolicRangeBoundChecks context surfaceStop) :
      SymbolicRangeChecks context .toInclusive none (some surfaceStop)
  | exclusive
      (start : SymbolicRangeBoundChecks context surfaceStart)
      (stop : SymbolicRangeBoundChecks context surfaceStop) :
      SymbolicRangeChecks context .exclusive
        (some surfaceStart) (some surfaceStop)
  | inclusive
      (start : SymbolicRangeBoundChecks context surfaceStart)
      (stop : SymbolicRangeBoundChecks context surfaceStop) :
      SymbolicRangeChecks context .inclusive
        (some surfaceStart) (some surfaceStop)

/-- Range bounds use the ordinary recursive expression-checking relation and
    expose the exact `i32` core term consumed by the loop. -/
inductive RangeBoundSpecializes
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy)
    (symbolic : SymbolicBodyContext)
    (concrete : SurfaceElaboration.Context)
    (contexts : symbolic.Specializes substitution groundReturnType concrete) :
    Surface.RangeBound → Core.Expr → Prop where
  | integer
      (checked : ExprCheckingDerivationSpecializes substitution groundReturnType
        symbolic concrete contexts (.literal (.integer text))
        (.scalar (.signed .i32)) (.scalar (.signed .i32)) core) :
      RangeBoundSpecializes substitution groundReturnType symbolic concrete
        contexts (.integer text) core
  | postfix
      (formed : Surface.RangeBoundPostfix surfaceExpression)
      (checked : ExprCheckingDerivationSpecializes substitution groundReturnType
        symbolic concrete contexts surfaceExpression (.scalar (.signed .i32))
        (.scalar (.signed .i32)) core) :
      RangeBoundSpecializes substitution groundReturnType symbolic concrete
        contexts (.postfix surfaceExpression) core

inductive RangeSpecializes
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy)
    (symbolic : SymbolicBodyContext)
    (concrete : SurfaceElaboration.Context)
    (contexts : symbolic.Specializes substitution groundReturnType concrete) :
    Surface.RangeKind → Option Surface.RangeBound →
      Option Surface.RangeBound → Core.Expr → Option Core.Expr → Bool → Prop where
  | full : RangeSpecializes substitution groundReturnType symbolic concrete
      contexts .full none none (.value (.signed .i32 0)) none false
  | from
      (start : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStart coreStart) :
      RangeSpecializes substitution groundReturnType symbolic concrete contexts
        .from (some surfaceStart) none coreStart none false
  | toExclusive
      (stop : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStop coreStop) :
      RangeSpecializes substitution groundReturnType symbolic concrete contexts
        .toExclusive none (some surfaceStop) (.value (.signed .i32 0))
        (some coreStop) false
  | toInclusive
      (stop : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStop coreStop) :
      RangeSpecializes substitution groundReturnType symbolic concrete contexts
        .toInclusive none (some surfaceStop) (.value (.signed .i32 0))
        (some coreStop) true
  | exclusive
      (start : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStart coreStart)
      (stop : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStop coreStop) :
      RangeSpecializes substitution groundReturnType symbolic concrete contexts
        .exclusive (some surfaceStart) (some surfaceStop) coreStart
        (some coreStop) false
  | inclusive
      (start : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStart coreStart)
      (stop : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStop coreStop) :
      RangeSpecializes substitution groundReturnType symbolic concrete contexts
        .inclusive (some surfaceStart) (some surfaceStop) coreStart
        (some coreStop) true

theorem RangeBoundSpecializes.symbolicCheck
    (specialized : RangeBoundSpecializes substitution groundReturnType symbolicContext
      concrete contexts surface core) :
    SymbolicRangeBoundChecks symbolicContext surface := by
  cases specialized with
  | integer checked => exact .integer checked.symbolicCheck
  | «postfix» formed checked => exact .postfix formed checked.symbolicCheck

theorem RangeBoundSpecializes.lowers
    (specialized : RangeBoundSpecializes substitution groundReturnType symbolicContext
      concrete contexts surface core) :
    SurfaceElaboration.RangeBoundLowers concrete surface core := by
  cases specialized with
  | integer checked => exact .integer checked.concreteCheck.2
  | «postfix» formed checked => exact .postfix formed checked.concreteCheck.2

theorem RangeSpecializes.symbolicChecks
    (specialized : RangeSpecializes substitution groundReturnType symbolicContext
      concrete contexts kind start stop coreStart coreStop isInclusive) :
    SymbolicRangeChecks symbolicContext kind start stop := by
  cases specialized with
  | full => exact .full
  | «from» start => exact .from start.symbolicCheck
  | toExclusive stop => exact .toExclusive stop.symbolicCheck
  | toInclusive stop => exact .toInclusive stop.symbolicCheck
  | exclusive start stop =>
      exact .exclusive start.symbolicCheck stop.symbolicCheck
  | inclusive start stop =>
      exact .inclusive start.symbolicCheck stop.symbolicCheck

theorem RangeSpecializes.lowers
    (specialized : RangeSpecializes substitution groundReturnType symbolicContext
      concrete contexts kind start stop coreStart coreStop isInclusive) :
    SurfaceElaboration.RangeLowers concrete kind start stop coreStart coreStop
      isInclusive := by
  cases specialized with
  | full => exact .full
  | «from» start => exact .from start.lowers
  | toExclusive stop => exact .toExclusive stop.lowers
  | toInclusive stop => exact .toInclusive stop.lowers
  | exclusive start stop => exact .exclusive start.lowers stop.lowers
  | inclusive start stop => exact .inclusive start.lowers stop.lowers

/-- Symbolic recognition of the two standard-library nominal range values
    supported by the current compiler's path-iterable rule. -/
inductive SymbolicNamedRangeHasElement
    (context : SymbolicBodyContext) (path : Surface.Path) : Bool → Prop where
  | exclusive
      (constructor : SurfaceElaboration.StructConstructorScheme)
      (selected : SurfaceElaboration.SelectsStructConstructor context.globals
        SurfaceElaboration.coreRangeTypePath constructor)
      (distinct : ∀ candidate,
        SurfaceElaboration.SelectsStructConstructor context.globals
          SurfaceElaboration.coreRangeInclusiveTypePath candidate →
        candidate.sourceType ≠ constructor.sourceType)
      (iterable : SymbolicExprInfers context (.path path)
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])) :
      SymbolicNamedRangeHasElement context path false
  | inclusive
      (constructor : SurfaceElaboration.StructConstructorScheme)
      (selected : SurfaceElaboration.SelectsStructConstructor context.globals
        SurfaceElaboration.coreRangeInclusiveTypePath constructor)
      (distinct : ∀ candidate,
        SurfaceElaboration.SelectsStructConstructor context.globals
          SurfaceElaboration.coreRangeTypePath candidate →
        candidate.sourceType ≠ constructor.sourceType)
      (iterable : SymbolicExprInfers context (.path path)
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])) :
      SymbolicNamedRangeHasElement context path true

/-- One nominal range path is recognized at symbolic types, grounded to the
    same canonical nominal instance, and projected through its exact concrete
    `start` and `end` field rows. -/
inductive NamedRangeSpecializes
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy)
    (symbolic : SymbolicBodyContext)
    (concrete : SurfaceElaboration.Context)
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (path : Surface.Path) : Core.Expr → Core.Expr → Bool → Prop where
  | exclusive
      (constructor : SurfaceElaboration.StructConstructorScheme)
      (selected : SurfaceElaboration.SelectsStructConstructor symbolic.globals
        SurfaceElaboration.coreRangeTypePath constructor)
      (distinct : ∀ candidate,
        SurfaceElaboration.SelectsStructConstructor symbolic.globals
          SurfaceElaboration.coreRangeInclusiveTypePath candidate →
        candidate.sourceType ≠ constructor.sourceType)
      (iterable : ExprInferenceDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts (.path path)
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        coreIterable)
      (startField endField : SurfaceElaboration.FieldEntry)
      (startSelected : SurfaceElaboration.SelectsField concrete
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "start" startField)
      (endSelected : SurfaceElaboration.SelectsField concrete
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "end" endField)
      (startType : startField.type = .scalar (.signed .i32))
      (endType : endField.type = .scalar (.signed .i32)) :
      NamedRangeSpecializes substitution groundReturnType symbolic concrete
        contexts path (.field coreIterable startField.field)
        (.field coreIterable endField.field) false
  | inclusive
      (constructor : SurfaceElaboration.StructConstructorScheme)
      (selected : SurfaceElaboration.SelectsStructConstructor symbolic.globals
        SurfaceElaboration.coreRangeInclusiveTypePath constructor)
      (distinct : ∀ candidate,
        SurfaceElaboration.SelectsStructConstructor symbolic.globals
          SurfaceElaboration.coreRangeTypePath candidate →
        candidate.sourceType ≠ constructor.sourceType)
      (iterable : ExprInferenceDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts (.path path)
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        coreIterable)
      (startField endField : SurfaceElaboration.FieldEntry)
      (startSelected : SurfaceElaboration.SelectsField concrete
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "start" startField)
      (endSelected : SurfaceElaboration.SelectsField concrete
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "end" endField)
      (startType : startField.type = .scalar (.signed .i32))
      (endType : endField.type = .scalar (.signed .i32)) :
      NamedRangeSpecializes substitution groundReturnType symbolic concrete
        contexts path (.field coreIterable startField.field)
        (.field coreIterable endField.field) true

theorem NamedRangeSpecializes.symbolic
    (specialized : NamedRangeSpecializes substitution groundReturnType
      symbolicContext concrete contexts path coreStart coreStop isInclusive) :
    SymbolicNamedRangeHasElement symbolicContext path isInclusive := by
  cases specialized with
  | exclusive constructor selected distinct iterable startField endField startSelected
      endSelected startType endType =>
      exact .exclusive constructor selected distinct iterable.symbolicInference
  | inclusive constructor selected distinct iterable startField endField startSelected
      endSelected startType endType =>
      exact .inclusive constructor selected distinct iterable.symbolicInference

theorem NamedRangeSpecializes.lowers
    (specialized : NamedRangeSpecializes substitution groundReturnType
      symbolicContext concrete contexts path coreStart coreStop isInclusive) :
    SurfaceElaboration.NamedRangeLowers concrete path coreStart coreStop
      isInclusive := by
  cases specialized with
  | exclusive constructor selected distinct iterable startField endField startSelected
      endSelected startType endType =>
      exact .exclusive constructor (contexts.selectsStructConstructor selected)
        iterable.concreteInference.2 startField endField startSelected endSelected
        startType endType
  | inclusive constructor selected distinct iterable startField endField startSelected
      endSelected startType endType =>
      exact .inclusive constructor (contexts.selectsStructConstructor selected)
        iterable.concreteInference.2 startField endField startSelected endSelected
        startType endType

inductive SymbolicForIterableHasElement
    (context : SymbolicBodyContext) :
    Surface.ForIterable → Static.Ty → Prop where
  | array
      (iterable : SymbolicExprInfers context (.path path)
        (.array elementType length)) :
      SymbolicForIterableHasElement context (.path path) elementType
  | slice
      (iterable : SymbolicExprInfers context (.path path)
        (.slice elementType)) :
      SymbolicForIterableHasElement context (.path path) elementType
  | namedRange
      (range : SymbolicNamedRangeHasElement context path inclusive) :
      SymbolicForIterableHasElement context (.path path)
        (.scalar (.signed .i32))
  | range
      (checked : SymbolicRangeChecks context kind surfaceStart surfaceStop) :
      SymbolicForIterableHasElement context
        (.range kind surfaceStart surfaceStop) (.scalar (.signed .i32))

/-- Parameter bindings are retained in the same newest-first order produced by
    repeated concrete `bindLocal` allocation. Source parameter names are
    declaration-wide unique, but preserving allocator order also makes the
    symbolic and concrete body contexts structurally compositional. -/
inductive SymbolicParametersBind :
    List Surface.Parameter → List Static.Ty →
      List SymbolicLocalBinding → Prop where
  | nil : SymbolicParametersBind [] [] []
  | named
      (tail : SymbolicParametersBind surfaceTail typeTail bindingTail) :
      SymbolicParametersBind (.named name annotation :: surfaceTail)
        (type :: typeTail) (bindingTail ++ [{ name := name, type := type }])
  | selfValue
      (tail : SymbolicParametersBind surfaceTail typeTail bindingTail) :
      SymbolicParametersBind (.selfValue annotation :: surfaceTail)
        (type :: typeTail) (bindingTail ++ [{ name := "self", type }])
  | selfReference
      (tail : SymbolicParametersBind surfaceTail typeTail bindingTail) :
      SymbolicParametersBind (.selfReference :: surfaceTail)
        (type :: typeTail) (bindingTail ++ [{ name := "self", type }])

theorem SymbolicParametersBind.lengths
    (bound : SymbolicParametersBind surface parameters bindings) :
    parameters.length = surface.length := by
  induction bound with
  | nil => rfl
  | named tail tailIH => simp [tailIH]
  | selfValue tail tailIH => simp [tailIH]
  | selfReference tail tailIH => simp [tailIH]

mutual
  inductive SymbolicStmtsWellTyped :
      SymbolicBodyContext → Bool → List Surface.Stmt → Prop where
    | nil : SymbolicStmtsWellTyped context inLoop []
    | expression
        (head : SymbolicExprInfers context surfaceExpression type)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.expression surfaceExpression :: surfaceTail)
    | letInferred
        (initializer : SymbolicExprInfers context surfaceInitializer type)
        (tail : SymbolicStmtsWellTyped (context.bind name type)
          inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.letLocal name none (some surfaceInitializer) :: surfaceTail)
    | letAnnotated
        (annotation : TypeRetains context.globals surfaceType type)
        (initializer : SymbolicExprChecks context surfaceInitializer type)
        (tail : SymbolicStmtsWellTyped (context.bind name type)
          inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.letLocal name (some surfaceType) (some surfaceInitializer) :: surfaceTail)
    | letUninitialized
        (annotation : TypeRetains context.globals surfaceType type)
        (tail : SymbolicStmtsWellTyped (context.bind name type)
          inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.letLocal name (some surfaceType) none :: surfaceTail)
    | returnUnit
        (unit : context.returnType = .unit)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.returnValue none :: surfaceTail)
    | returnValue
        (value : SymbolicExprChecks context surfaceValue context.returnType)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.returnValue (some surfaceValue) :: surfaceTail)
    | ifThenElse
        (condition : SymbolicExprChecks context surfaceCondition (.scalar .bool))
        (thenBody : SymbolicStmtsWellTyped context inLoop surfaceThen)
        (elseBody : SymbolicStmtsWellTyped context inLoop surfaceElse)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.ifThenElse surfaceCondition surfaceThen surfaceElse :: surfaceTail)
    | whileLoop
        (condition : SymbolicExprChecks context surfaceCondition (.scalar .bool))
        (body : SymbolicStmtsWellTyped context true surfaceBody)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.whileLoop surfaceCondition surfaceBody :: surfaceTail)
    | forLoop
        (iterable : SymbolicForIterableHasElement context
          surfaceIterable elementType)
        (body : SymbolicStmtsWellTyped (context.bind name elementType)
          true surfaceBody)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.forLoop name surfaceIterable surfaceBody :: surfaceTail)
    | breakLoop
        (inside : inLoop = true)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop (.breakLoop :: surfaceTail)
    | continueLoop
        (inside : inLoop = true)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop (.continueLoop :: surfaceTail)
    | block
        (body : SymbolicStmtsWellTyped context inLoop surfaceBody)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.block surfaceBody :: surfaceTail)
end

/-- Statement specialization consumes exact-output recursive expression
    derivations. The symbolic judgment, grounded type, and emitted child term
    therefore come from one occurrence witness rather than parallel premises. -/
inductive StmtsSpecialize
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy) :
    SymbolicBodyContext → SurfaceElaboration.Context → VarId → Bool →
      List Surface.Stmt → Core.Stmt → VarId → Prop where
  | nil
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop [] .skip next
  | expression
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (head : ExprInferenceDerivationSpecializes substitution groundReturnType
        symbolic concrete contexts surfaceExpression symbolicType groundType
        coreExpression)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.expression surfaceExpression :: surfaceTail)
        (.sequence (.expression coreExpression) coreTail) final
  | letInferred
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (initializer : ExprInferenceDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts surfaceInitializer
        symbolicType groundType coreInitializer)
      (coreType : groundType.toCore concrete.monomorphization = some loweredType)
      (tail : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name symbolicType)
        (concrete.bindLocal name next groundType) (next + 1) inLoop
        surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.letLocal name none (some surfaceInitializer) :: surfaceTail)
        (.letLocal next loweredType coreInitializer coreTail) final
  | letAnnotated
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (annotation : TypeRetains symbolic.globals surfaceType symbolicType)
      (initializer : ExprCheckingDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts surfaceInitializer
        symbolicType groundType coreInitializer)
      (coreType : groundType.toCore concrete.monomorphization = some loweredType)
      (tail : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name symbolicType)
        (concrete.bindLocal name next groundType) (next + 1) inLoop
        surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.letLocal name (some surfaceType) (some surfaceInitializer) :: surfaceTail)
        (.letLocal next loweredType coreInitializer coreTail) final
  | letUninitialized
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (annotation : TypeRetains symbolic.globals surfaceType symbolicType)
      (typeGrounds : symbolicType.instantiate substitution = some groundType)
      (coreType : groundType.toCore concrete.monomorphization = some loweredType)
      (tail : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name symbolicType)
        (concrete.bindLocal name next groundType) (next + 1) inLoop
        surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.letLocal name (some surfaceType) none :: surfaceTail)
        (.letUninitialized next loweredType coreTail) final
  | returnUnit
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (unit : symbolic.returnType = .unit)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.returnValue none :: surfaceTail)
        (.sequence (.returnValue none) coreTail) final
  | returnValue
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (value : ExprCheckingDerivationSpecializes substitution groundReturnType
        symbolic concrete contexts surfaceValue symbolic.returnType
        groundReturnType coreValue)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.returnValue (some surfaceValue) :: surfaceTail)
        (.sequence (.returnValue (some coreValue)) coreTail) final
  | ifThenElse
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (condition : ExprCheckingDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts surfaceCondition
        (.scalar .bool) (.scalar .bool) coreCondition)
      (thenBody : StmtsSpecialize substitution groundReturnType symbolic concrete
        next inLoop surfaceThen coreThen thenNext)
      (elseBody : StmtsSpecialize substitution groundReturnType symbolic concrete
        next inLoop surfaceElse coreElse elseNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        (Nat.max thenNext elseNext) inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.ifThenElse surfaceCondition surfaceThen surfaceElse :: surfaceTail)
        (.sequence (.ifThenElse coreCondition coreThen coreElse) coreTail) final
  | whileLoop
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (condition : ExprCheckingDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts surfaceCondition
        (.scalar .bool) (.scalar .bool) coreCondition)
      (body : StmtsSpecialize substitution groundReturnType symbolic concrete next
        true surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.whileLoop surfaceCondition surfaceBody :: surfaceTail)
        (.sequence (.whileLoop coreCondition coreBody) coreTail) final
  | forArray
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (iterable : ExprInferenceDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts (.path path)
        (.array elementType length) (.array groundElement groundLength)
        coreIterable)
      (body : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name elementType)
        (concrete.bindLocal name next groundElement) (next + 1) true
        surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.forLoop name (.path path) surfaceBody :: surfaceTail)
        (.sequence (.forValues next coreIterable coreBody) coreTail) final
  | forSlice
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (iterable : ExprInferenceDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts (.path path)
        (.slice elementType) (.slice groundElement) coreIterable)
      (body : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name elementType)
        (concrete.bindLocal name next groundElement) (next + 1) true
        surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.forLoop name (.path path) surfaceBody :: surfaceTail)
        (.sequence (.forValues next coreIterable coreBody) coreTail) final
  | forNamedRange
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (range : NamedRangeSpecializes substitution groundReturnType symbolic
        concrete contexts path coreStart coreStop inclusive)
      (body : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name (.scalar (.signed .i32)))
        (concrete.bindLocal name next (.scalar (.signed .i32))) (next + 1) true
        surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.forLoop name (.path path) surfaceBody :: surfaceTail)
        (.sequence (.forRange next coreStart (some coreStop) inclusive coreBody)
          coreTail) final
  | forRange
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (range : RangeSpecializes substitution groundReturnType symbolic concrete
        contexts kind surfaceStart surfaceStop coreStart coreStop inclusive)
      (body : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name (.scalar (.signed .i32)))
        (concrete.bindLocal name next (.scalar (.signed .i32))) (next + 1) true
        surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.forLoop name (.range kind surfaceStart surfaceStop) surfaceBody :: surfaceTail)
        (.sequence (.forRange next coreStart coreStop inclusive coreBody) coreTail) final
  | breakLoop
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (inside : inLoop = true)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.breakLoop :: surfaceTail) (.sequence .breakLoop coreTail) final
  | continueLoop
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (inside : inLoop = true)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.continueLoop :: surfaceTail) (.sequence .continueLoop coreTail) final
  | block
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (body : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.block surfaceBody :: surfaceTail) (.sequence coreBody coreTail) final

theorem StmtsSpecialize.symbolic
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    SymbolicStmtsWellTyped symbolic inLoop surface := by
  induction specialized with
  | nil => exact .nil
  | expression contexts bounded head tail tailIH =>
      exact .expression head.symbolicInference tailIH
  | letInferred contexts bounded initializer coreType tail tailIH =>
      exact .letInferred initializer.symbolicInference tailIH
  | letAnnotated contexts bounded annotation initializer coreType tail tailIH =>
      exact .letAnnotated annotation initializer.symbolicCheck tailIH
  | letUninitialized contexts bounded annotation typeGrounds coreType tail tailIH =>
      exact .letUninitialized annotation tailIH
  | returnUnit contexts bounded unit tail tailIH => exact .returnUnit unit tailIH
  | returnValue contexts bounded value tail tailIH =>
      exact .returnValue value.symbolicCheck tailIH
  | ifThenElse contexts bounded condition thenBody elseBody tail
      thenIH elseIH tailIH =>
      exact .ifThenElse condition.symbolicCheck thenIH elseIH tailIH
  | whileLoop contexts bounded condition body tail bodyIH tailIH =>
      exact .whileLoop condition.symbolicCheck bodyIH tailIH
  | forArray contexts bounded iterable body tail bodyIH tailIH =>
      exact .forLoop (.array iterable.symbolicInference) bodyIH tailIH
  | forSlice contexts bounded iterable body tail bodyIH tailIH =>
      exact .forLoop (.slice iterable.symbolicInference) bodyIH tailIH
  | forNamedRange contexts bounded range body tail bodyIH tailIH =>
      exact .forLoop (.namedRange range.symbolic) bodyIH tailIH
  | forRange contexts bounded range body tail bodyIH tailIH =>
      exact .forLoop (.range range.symbolicChecks) bodyIH tailIH
  | breakLoop contexts bounded inside tail tailIH => exact .breakLoop inside tailIH
  | continueLoop contexts bounded inside tail tailIH =>
      exact .continueLoop inside tailIH
  | block contexts bounded body tail bodyIH tailIH => exact .block bodyIH tailIH

theorem StmtsSpecialize.lowers
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    SurfaceElaboration.StmtsLower concrete next surface core final := by
  induction specialized with
  | nil => exact .nil
  | expression contexts bounded head tail tailIH =>
      exact .expression head.concreteInference.2 tailIH
  | letInferred contexts bounded initializer coreType tail tailIH =>
      exact .letInferred bounded.fresh initializer.concreteInference.2 coreType tailIH
  | letAnnotated contexts bounded annotation initializer coreType tail tailIH =>
      exact .letAnnotated bounded.fresh
        (annotation.specializes contexts initializer.concreteCheck.1)
        initializer.concreteCheck.2 coreType tailIH
  | letUninitialized contexts bounded annotation typeGrounds coreType tail tailIH =>
      exact .letUninitialized bounded.fresh
        (annotation.specializes contexts typeGrounds) coreType tailIH
  | returnUnit contexts bounded unit tail tailIH => exact .returnUnit tailIH
  | returnValue contexts bounded value tail tailIH =>
      exact .returnValue value.concreteCheck.2 tailIH
  | ifThenElse contexts bounded condition thenBody elseBody tail
      thenIH elseIH tailIH =>
      exact .ifThenElse condition.concreteCheck.2 thenIH elseIH tailIH
  | whileLoop contexts bounded condition body tail bodyIH tailIH =>
      exact .whileLoop condition.concreteCheck.2 bodyIH tailIH
  | forArray contexts bounded iterable body tail bodyIH tailIH =>
      exact .forArray bounded.fresh iterable.concreteInference.2 bodyIH tailIH
  | forSlice contexts bounded iterable body tail bodyIH tailIH =>
      exact .forSlice bounded.fresh iterable.concreteInference.2 bodyIH tailIH
  | forNamedRange contexts bounded range body tail bodyIH tailIH =>
      exact .forNamedRange bounded.fresh range.lowers bodyIH tailIH
  | forRange contexts bounded range body tail bodyIH tailIH =>
      exact .forRange bounded.fresh range.lowers bodyIH tailIH
  | breakLoop contexts bounded inside tail tailIH => exact .breakLoop tailIH
  | continueLoop contexts bounded inside tail tailIH => exact .continueLoop tailIH
  | block contexts bounded body tail bodyIH tailIH => exact .block bodyIH tailIH

theorem StmtsSpecialize.contexts
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    symbolic.Specializes substitution groundReturnType concrete := by
  cases specialized <;> assumption

theorem StmtsSpecialize.initialBounded
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    SurfaceElaboration.LocalIdsBelow concrete next := by
  cases specialized <;> assumption

theorem StmtsSpecialize.final_ge
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    next ≤ final := by
  induction specialized with
  | nil => exact Nat.le_refl _
  | expression contexts bounded head tail tailIH => exact tailIH
  | letInferred contexts bounded initializer coreType tail tailIH =>
      exact Nat.le_trans (Nat.le_succ _) tailIH
  | letAnnotated contexts bounded annotation initializer coreType tail tailIH =>
      exact Nat.le_trans (Nat.le_succ _) tailIH
  | letUninitialized contexts bounded annotation typeGrounds coreType tail tailIH =>
      exact Nat.le_trans (Nat.le_succ _) tailIH
  | returnUnit contexts bounded unit tail tailIH => exact tailIH
  | returnValue contexts bounded value tail tailIH => exact tailIH
  | ifThenElse contexts bounded condition thenBody elseBody tail
      thenIH elseIH tailIH =>
      exact Nat.le_trans (Nat.le_trans thenIH (Nat.le_max_left _ _)) tailIH
  | whileLoop contexts bounded condition body tail bodyIH tailIH =>
      exact Nat.le_trans bodyIH tailIH
  | forArray contexts bounded iterable body tail bodyIH tailIH =>
      exact Nat.le_trans (Nat.le_trans (Nat.le_succ _) bodyIH) tailIH
  | forSlice contexts bounded iterable body tail bodyIH tailIH =>
      exact Nat.le_trans (Nat.le_trans (Nat.le_succ _) bodyIH) tailIH
  | forNamedRange contexts bounded range body tail bodyIH tailIH =>
      exact Nat.le_trans (Nat.le_trans (Nat.le_succ _) bodyIH) tailIH
  | forRange contexts bounded range body tail bodyIH tailIH =>
      exact Nat.le_trans (Nat.le_trans (Nat.le_succ _) bodyIH) tailIH
  | breakLoop contexts bounded inside tail tailIH => exact tailIH
  | continueLoop contexts bounded inside tail tailIH => exact tailIH
  | block contexts bounded body tail bodyIH tailIH => exact Nat.le_trans bodyIH tailIH

theorem StmtsSpecialize.finalBounded
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    SurfaceElaboration.LocalIdsBelow concrete final :=
  specialized.initialBounded.mono specialized.final_ge

def FunctionBodySymbolicallyTyped
    (globals : SurfaceElaboration.Context)
    (assumptions : List Static.TraitPattern)
    (parameters : List Surface.Parameter)
    (parameterTypes : List Static.Ty)
    (returnType : Static.Ty)
    (body : List Surface.Stmt) : Prop :=
  ∃ bindings,
    SymbolicParametersBind parameters parameterTypes bindings ∧
      SymbolicStmtsWellTyped {
        globals
        assumptions
        returnType
        locals := bindings
      } false body

def symbolicMethodParameterTypes (scheme : Static.MethodScheme) : List Static.Ty :=
  match scheme.receiverMode with
  | .none => scheme.argumentTypes
  | .value | .explicit => scheme.receiverType :: scheme.argumentTypes
  | .reference => .reference scheme.receiverType :: scheme.argumentTypes

/-- Parameters allocate dense core local IDs from left to right and extend the
    body context. A receiver type is present only while lowering an impl method
    or a trait method instance. -/
inductive ParametersLower :
    SurfaceElaboration.Context → Option Static.GroundTy → VarId →
      List Surface.Parameter → List Static.GroundTy →
      List (VarId × Core.Ty) → SurfaceElaboration.Context → VarId → Prop where
  | nil : ParametersLower context none next [] [] [] context next
  | named
      (notShadowed : SurfaceElaboration.NoLocalNamed context.locals name)
      (type : SurfaceElaboration.TypeGrounds context surfaceType groundType)
      (coreType : groundType.toCore context.monomorphization = some loweredType)
      (tail : ParametersLower (context.bindLocal name next groundType) none (next + 1)
        surfaceTail groundTail coreTail result final) :
      ParametersLower context none next
        (.named name surfaceType :: surfaceTail)
        (groundType :: groundTail) ((next, loweredType) :: coreTail) result final
  | namedReceiver
      (notShadowed : SurfaceElaboration.NoLocalNamed context.locals name)
      (type : SurfaceElaboration.TypeGrounds context surfaceType receiverType)
      (coreType : receiverType.toCore context.monomorphization = some loweredType)
      (tail : ParametersLower (context.bindLocal name next receiverType) none (next + 1)
        surfaceTail groundTail coreTail result final) :
      ParametersLower context (some receiverType) next
        (.named name surfaceType :: surfaceTail)
        (receiverType :: groundTail) ((next, loweredType) :: coreTail) result final
  | selfValue
      (notShadowed : SurfaceElaboration.NoLocalNamed context.locals "self")
      (tail : ParametersLower (context.bindLocal "self" next receiverType)
        none (next + 1) surfaceTail groundTail coreTail result final)
      (coreType : receiverType.toCore context.monomorphization = some loweredType) :
      ParametersLower context (some receiverType) next
        (.selfValue none :: surfaceTail)
        (receiverType :: groundTail) ((next, loweredType) :: coreTail) result final
  | selfValueTyped
      (notShadowed : SurfaceElaboration.NoLocalNamed context.locals "self")
      (annotation : SurfaceElaboration.TypeGrounds context surfaceType receiverType)
      (tail : ParametersLower (context.bindLocal "self" next receiverType)
        none (next + 1) surfaceTail groundTail coreTail result final)
      (coreType : receiverType.toCore context.monomorphization = some loweredType) :
      ParametersLower context (some receiverType) next
        (.selfValue (some surfaceType) :: surfaceTail)
        (receiverType :: groundTail) ((next, loweredType) :: coreTail) result final
  | selfReference
      (notShadowed : SurfaceElaboration.NoLocalNamed context.locals "self")
      (coreReferent : receiverType.toCore context.monomorphization = some referent)
      (tail : ParametersLower
        (context.bindLocal "self" next (.reference receiverType))
        none (next + 1) surfaceTail groundTail coreTail result final) :
      ParametersLower context (some receiverType) next
        (.selfReference :: surfaceTail)
        (.reference receiverType :: groundTail)
        ((next, .reference referent) :: coreTail) result final

/-- Symbolic parameter retention and concrete dense allocation extend one
    specializing context in lockstep. The theorem is lookup-order exact because
    `SymbolicParametersBind` and `ParametersLower` both retain newest bindings
    first. -/
theorem SymbolicParametersBind.specializes
    {symbolic : SymbolicBodyContext}
    (bound : SymbolicParametersBind surface symbolicTypes symbolicBindings)
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (typesGround : Static.instantiateTypes substitution symbolicTypes =
      some groundTypes)
    (lowered : ParametersLower concrete receiver next surface groundTypes
      coreParameters result final) :
    (symbolic.bindMany symbolicBindings).Specializes substitution
      groundReturnType result := by
  induction bound generalizing symbolic concrete receiver next groundTypes
      coreParameters result final with
  | nil =>
      simp [Static.instantiateTypes] at typesGround
      subst groundTypes
      cases lowered
      simpa [SymbolicBodyContext.bindMany] using contexts
  | @named surfaceTail typeTail bindingTail name annotation type tail tailIH =>
      cases headGrounded : type.instantiate substitution with
      | none => simp [Static.instantiateTypes, headGrounded] at typesGround
      | some groundType =>
          cases tailGrounded : Static.instantiateTypes substitution typeTail with
          | none =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
          | some groundTail =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
              subst groundTypes
              cases lowered with
              | named notShadowed typeLowered coreType loweredTail =>
                  have tailContexts := tailIH
                    (contexts.bind name next type groundType headGrounded)
                    tailGrounded loweredTail
                  simpa [SymbolicBodyContext.bindMany, List.foldr_append] using
                    tailContexts
              | namedReceiver notShadowed typeLowered coreType loweredTail =>
                  have tailContexts := tailIH
                    (contexts.bind name next type groundType headGrounded)
                    tailGrounded loweredTail
                  simpa [SymbolicBodyContext.bindMany, List.foldr_append] using
                    tailContexts
  | @selfValue surfaceTail typeTail bindingTail annotation type tail tailIH =>
      cases headGrounded : type.instantiate substitution with
      | none => simp [Static.instantiateTypes, headGrounded] at typesGround
      | some groundType =>
          cases tailGrounded : Static.instantiateTypes substitution typeTail with
          | none =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
          | some groundTail =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
              subst groundTypes
              cases lowered with
              | selfValue notShadowed loweredTail coreType =>
                  have tailContexts := tailIH
                    (contexts.bind "self" next type _ headGrounded)
                    tailGrounded loweredTail
                  simpa [SymbolicBodyContext.bindMany, List.foldr_append] using
                    tailContexts
              | selfValueTyped notShadowed annotationLowered loweredTail coreType =>
                  have tailContexts := tailIH
                    (contexts.bind "self" next type groundType headGrounded)
                    tailGrounded loweredTail
                  simpa [SymbolicBodyContext.bindMany, List.foldr_append] using
                    tailContexts
  | @selfReference surfaceTail typeTail bindingTail type tail tailIH =>
      cases headGrounded : type.instantiate substitution with
      | none => simp [Static.instantiateTypes, headGrounded] at typesGround
      | some groundType =>
          cases tailGrounded : Static.instantiateTypes substitution typeTail with
          | none =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
          | some groundTail =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
              subst groundTypes
              cases lowered with
              | selfReference notShadowed coreReferent loweredTail =>
                  have tailContexts := tailIH
                    (contexts.bind "self" next type _ headGrounded)
                    tailGrounded loweredTail
                  simpa [SymbolicBodyContext.bindMany, List.foldr_append] using
                    tailContexts

/-- One monomorphic function artifact is derived from one declaration-wide
    symbolic body derivation. Parameters, return interpretation, local-ID
    allocation, statement specialization, and the emitted core function all
    share their exact source occurrence in this single witness. -/
inductive FunctionSpecializes
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.Function)
    (scheme : Static.FunctionScheme)
    (resolved : Static.FunctionInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (instantiated : Static.FunctionInstantiates baseContext.implementations
        scheme substitution resolved)
      (baseLocals : baseContext.locals = [])
      (symbolicBindings : List SymbolicLocalBinding)
      (symbolicParameters : SymbolicParametersBind surface.parameters
        scheme.parameterTypes symbolicBindings)
      (coreParameters : List (VarId × Core.Ty))
      (bodyContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (parameters : ParametersLower { baseContext with substitution }
        none 0 surface.parameters resolved.parameterTypes coreParameters
        bodyContext nextLocal)
      (returnRetained : ReturnTypeRetains baseContext surface.name
        surface.returnType scheme.returnType)
      (coreReturnType : Core.Ty)
      (returnTypeCore : resolved.returnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (coreBody : Core.Stmt)
      (finalLocal : VarId)
      (body : StmtsSpecialize substitution resolved.returnType {
          globals := baseContext
          assumptions := scheme.requirements
          returnType := scheme.returnType
          locals := symbolicBindings
        } bodyContext nextLocal false surface.body coreBody finalLocal)
      (definition : core = {
        id := resolved.function
        parameters := coreParameters
        returnType := coreReturnType
        body := some coreBody
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      FunctionSpecializes program baseContext surface scheme resolved core

/-- The independently checked result of lowering one monomorphic function
    instance. Generic substitution and instance identity are explicit inputs;
    the resulting core function must also satisfy the ordinary program typing
    judgment. -/
inductive FunctionLowers
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.Function)
    (scheme : Static.FunctionScheme)
    (monomorphicInstance : Static.FunctionInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (instantiated : Static.FunctionInstantiates baseContext.implementations
        scheme substitution monomorphicInstance)
      (declarationParameters : scheme.parameterTypes.length = surface.parameters.length)
      (groundParameters : List Static.GroundTy)
      (coreParameters : List (VarId × Core.Ty))
      (bodyContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (parameters : ParametersLower { baseContext with substitution := substitution }
        none 0 surface.parameters groundParameters coreParameters bodyContext nextLocal)
      (parameterTypes : groundParameters = monomorphicInstance.parameterTypes)
      (groundReturnType : Static.GroundTy)
      (returnType : ReturnTypeGrounds { baseContext with substitution := substitution }
        surface.name surface.returnType groundReturnType)
      (selectedReturnType : groundReturnType = monomorphicInstance.returnType)
      (coreReturnType : Core.Ty)
      (returnTypeCore : groundReturnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (coreBody : Core.Stmt)
      (finalLocal : VarId)
      (body : SurfaceElaboration.StmtsLower bodyContext nextLocal
        surface.body coreBody finalLocal)
      (definition : core = {
        id := monomorphicInstance.function
        parameters := coreParameters
        returnType := coreReturnType
        body := some coreBody
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      FunctionLowers program baseContext surface scheme monomorphicInstance core

theorem FunctionSpecializes.symbolic
    (specialized : FunctionSpecializes program baseContext surface scheme
      resolved core) :
    FunctionBodySymbolicallyTyped baseContext scheme.requirements
      surface.parameters scheme.parameterTypes scheme.returnType surface.body := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      exact ⟨symbolicBindings, symbolicParameters, body.symbolic⟩

theorem FunctionSpecializes.lowers
    (specialized : FunctionSpecializes program baseContext surface scheme
      resolved core) :
    FunctionLowers program baseContext surface scheme resolved core := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      have initialContexts := SymbolicBodyContext.declarationSpecializes
        baseContext scheme.requirements scheme.returnType substitution
        resolved.returnType baseLocals instantiated.returnType
      apply FunctionLowers.intro
          (substitution := substitution)
          (groundParameters := resolved.parameterTypes)
          (coreParameters := coreParameters)
          (bodyContext := bodyContext)
          (nextLocal := nextLocal)
          (groundReturnType := resolved.returnType)
          (coreReturnType := coreReturnType)
          (coreBody := coreBody)
          (finalLocal := finalLocal)
      · exact instantiated
      · exact symbolicParameters.lengths
      · exact parameters
      · rfl
      · exact returnRetained.specializes initialContexts instantiated.returnType
      · rfl
      · exact returnTypeCore
      · exact body.lowers
      · exact definition
      · exact target
      · exact member
      · exact typed

theorem FunctionSpecializes.instanceTypes
    (specialized : FunctionSpecializes program baseContext surface scheme
      resolved core) :
    ∃ substitution,
      Static.instantiateTypes substitution scheme.parameterTypes =
        some resolved.parameterTypes ∧
      scheme.returnType.instantiate substitution = some resolved.returnType := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      exact ⟨substitution, instantiated.parameterTypes, instantiated.returnType⟩

theorem FunctionSpecializes.parameterContexts
    (specialized : FunctionSpecializes program baseContext surface scheme
      resolved core) :
    ∃ substitution symbolicBindings bodyContext,
      ({
        globals := baseContext
        assumptions := scheme.requirements
        returnType := scheme.returnType
        locals := symbolicBindings
      } : SymbolicBodyContext).Specializes substitution resolved.returnType
        bodyContext := by
  cases specialized with
  | intro substitution instantiated baseLocals actualBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters returnRetained
      coreReturnType returnTypeCore coreBody finalLocal body definition target
      member typed =>
      have initial := SymbolicBodyContext.declarationSpecializes
        baseContext scheme.requirements scheme.returnType substitution
        resolved.returnType baseLocals instantiated.returnType
      have parameterContexts := symbolicParameters.specializes initial
        instantiated.parameterTypes parameters
      exact ⟨substitution, actualBindings, bodyContext, by
        simpa [SymbolicBodyContext.bindMany_eq, baseLocals] using
          parameterContexts⟩

/-- Closed nongeneric functions are the common boundary used by executable
    examples and zero-argument entrypoints. This theorem keeps the semantic
    obligations visible while discharging the structurally empty substitution
    and parameter traversal once. -/
theorem FunctionLowers.closedNongeneric
    (instantiated : Static.FunctionInstantiates baseContext.implementations
      scheme {} monomorphicInstance)
    (surfaceParameters : surface.parameters = [])
    (schemeParameters : scheme.parameterTypes = [])
    (instanceParameters : monomorphicInstance.parameterTypes = [])
    (groundReturnType : Static.GroundTy)
    (returnType : ReturnTypeGrounds { baseContext with substitution := {} }
      surface.name surface.returnType groundReturnType)
    (selectedReturnType : groundReturnType = monomorphicInstance.returnType)
    (coreReturnType : Core.Ty)
    (returnTypeCore : groundReturnType.toCore baseContext.monomorphization =
      some coreReturnType)
    (coreBody : Core.Stmt)
    (finalLocal : VarId)
    (body : SurfaceElaboration.StmtsLower
      { baseContext with substitution := {} } 0 surface.body coreBody finalLocal)
    (definition : core = {
      id := monomorphicInstance.function
      parameters := []
      returnType := coreReturnType
      body := some coreBody
    })
    (target : program.target = baseContext.target)
    (member : core ∈ program.functions)
    (typed : Typing.FunctionWellTyped program core) :
    FunctionLowers program baseContext surface scheme monomorphicInstance core := by
  apply FunctionLowers.intro
      (substitution := {})
      (groundParameters := [])
      (coreParameters := [])
      (bodyContext := { baseContext with substitution := {} })
      (nextLocal := 0)
      (groundReturnType := groundReturnType)
      (coreReturnType := coreReturnType)
      (coreBody := coreBody)
      (finalLocal := finalLocal)
  · exact instantiated
  · simp [schemeParameters, surfaceParameters]
  · simpa [surfaceParameters] using
      (ParametersLower.nil
        (context := { baseContext with substitution := {} }) (next := 0))
  · simpa [instanceParameters]
  · exact returnType
  · exact selectedReturnType
  · exact returnTypeCore
  · exact body
  · exact definition
  · exact target
  · exact member
  · exact typed

/-- Concrete lowering retains the ground instantiation that fixes the emitted
    parameter and return types of this specialization. -/
theorem FunctionLowers.instanceTypes
    (lowered : FunctionLowers program baseContext surface scheme
      monomorphicInstance core) :
    ∃ substitution,
      Static.instantiateTypes substitution scheme.parameterTypes =
        some monomorphicInstance.parameterTypes ∧
      scheme.returnType.instantiate substitution =
        some monomorphicInstance.returnType := by
  cases lowered with
  | intro substitution instantiated declarationParameters groundParameters
      coreParameters bodyContext nextLocal parameters parameterTypes
      groundReturnType returnType selectedReturnType coreReturnType
      returnTypeCore coreBody finalLocal body definition target member typed =>
      exact ⟨substitution, instantiated.parameterTypes,
        instantiated.returnType⟩

/-- Type-alias collection preserves the source target and assigns semantic
    generic parameter IDs. Expansion occurs in `TypeGrounds`, where recursive
    aliases have no finite derivation and are therefore rejected. -/
inductive CollectedTypeAlias
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (entry : SurfaceElaboration.TypeAliasEntry) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (name : Surface.Name)
      (isPublic : Bool)
      (surfaceParameters : List Surface.GenericParameter)
      (predicates : List Surface.WherePredicate)
      (target : Surface.TypeExpr)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some
        (.typeAlias name isPublic surfaceParameters predicates target))
      (headerKind : header.kind = .typeAlias)
      (entryMember : entry ∈ context.typeAliases)
      (declaration : entry.declaration = header.declaration)
      (entryModule : entry.moduleId = header.moduleId)
      (namesUnique : GenericParameterNamesUnique surfaceParameters)
      (parameters : GenericParametersLower (context.forModule header.moduleId)
        0 0 surfaceParameters
        entry.parameters finalType finalConst)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) entry.parameters)
        surfaceParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) entry.parameters)
        predicates whereRequirements)
      (entryRequirements : entry.requirements =
        genericRequirements ++ whereRequirements)
      (entryTarget : entry.target = target) :
      CollectedTypeAlias pack catalog context header entry

inductive CollectedFunctionScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.FunctionScheme) :
    SurfaceElaboration.Context → Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.Function)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (parameterTypes : List Static.Ty)
      (returnType : Static.Ty)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.function surface))
      (headerKind : header.kind = .function)
      (schemeMember : scheme ∈ context.functions)
      (declaration : scheme.declaration = header.declaration)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (parameters : ParameterTypesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.parameters parameterTypes)
      (schemeParameterTypes : scheme.parameterTypes = parameterTypes)
      (returned : ReturnTypeRetains
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.name surface.returnType returnType)
      (schemeReturnType : scheme.returnType = returnType)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements)
      (bodyScoped : SourceWellFormed.FunctionBodyWellScoped
        (context.forModule header.moduleId) surface.parameters surface.body)
      (bodyTyped : FunctionBodySymbolicallyTyped
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        scheme.requirements surface.parameters scheme.parameterTypes
        scheme.returnType surface.body) :
      CollectedFunctionScheme pack catalog context header scheme
        (withGenericParameters (context.forModule header.moduleId)
          genericParameters)

/-- A collected source function exposes the declaration occurrence that owns
    its callable scheme row. -/
theorem CollectedFunctionScheme.source_declaration
    (collected : CollectedFunctionScheme pack catalog context header scheme
      bodyContext) :
    ∃ address, header.source = .item address ∧
      scheme.declaration = header.declaration := by
  cases collected with
  | intro address _surface _genericParameters _parameterTypes _returnType
      _genericRequirements _whereRequirements source _headerMember
      _headerMatches _itemFound _headerKind _schemeMember declaration
      _namesUnique _parametersCollected _schemeParameters _parameters
      _schemeParameterTypes _returned _schemeReturnType _genericBounds
      _whereBounds _schemeRequirements _bodyScoped _bodyTyped =>
      exact ⟨address, source, declaration⟩

theorem CollectedFunctionScheme.signature_substitute_unique
    (collected : CollectedFunctionScheme pack catalog context header scheme
      bodyContext)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      scheme.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      scheme.genericParameters typeArguments constArguments)
    (leftParameters : Static.substituteTypes leftSubstitution
      scheme.parameterTypes = some leftParameterTypes)
    (rightParameters : Static.substituteTypes rightSubstitution
      scheme.parameterTypes = some rightParameterTypes)
    (leftReturn : scheme.returnType.substitute leftSubstitution =
      some leftReturnType)
    (rightReturn : scheme.returnType.substitute rightSubstitution =
      some rightReturnType) :
    leftParameterTypes = rightParameterTypes ∧
      leftReturnType = rightReturnType := by
  cases collected with
  | intro address surface genericParameters retainedParameterTypes
      retainedReturnType genericRequirements whereRequirements source
      headerMember headerMatches itemFound headerKind schemeMember declaration
      namesUnique parametersCollected schemeParameters parameters
      schemeParameterTypes returned schemeReturnType genericBounds whereBounds
      schemeRequirements bodyScoped bodyTyped =>
      rw [schemeParameters] at leftBound rightBound
      rw [schemeParameterTypes] at leftParameters rightParameters
      rw [schemeReturnType] at leftReturn rightReturn
      have parameterEquality :=
        parameters.substitute_eq_of_arguments leftBound rightBound
      have returnEquality := returned.substitute_eq_of_arguments
        leftBound rightBound
      rw [leftParameters, rightParameters] at parameterEquality
      rw [leftReturn, rightReturn] at returnEquality
      exact ⟨Option.some.inj parameterEquality,
        Option.some.inj returnEquality⟩

/-- A collected internal function artifact uses the exact generic declaration
    context exposed by scheme collection and one coupled body-specialization
    witness. The source occurrence is repeated only to index the specialized
    body; deterministic source-pack lookup prevents it from naming another
    function. -/
inductive CollectedFunctionLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.FunctionScheme)
    (resolved : Static.FunctionInstance)
    (core : Core.Function) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.Function)
      (bodyContext : SurfaceElaboration.Context)
      (source : header.source = .item address)
      (itemFound : pack.item? address = some (.function surface))
      (schemeCollected : CollectedFunctionScheme pack catalog baseContext
        header scheme bodyContext)
      (instanceMember : resolved ∈ baseContext.functionInstances)
      (instanceDeclaration : resolved.declaration = header.declaration)
      (specializes : FunctionSpecializes program bodyContext surface scheme
        resolved core) :
      CollectedFunctionLowers pack catalog program baseContext header scheme
        resolved core

inductive TraitMethodHeaders
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (parent : Declarations.ItemAddress) :
    Nat → List Surface.TraitMethod → List Nat → Prop where
  | nil : TraitMethodHeaders pack catalog parent index [] []
  | cons
      (header : Declarations.DeclarationHeader)
      (member : header ∈ catalog.headers)
      (source : header.source = .traitMethod parent index)
      (kind : header.kind = .traitMethod)
      (headerValid : Declarations.HeaderMatches pack header)
      (tail : TraitMethodHeaders pack catalog parent (index + 1)
        surfaceTail declarationTail) :
      TraitMethodHeaders pack catalog parent index (surfaceHead :: surfaceTail)
        (header.declaration :: declarationTail)

inductive TraitMethodParametersRetain (context : SurfaceElaboration.Context) :
    List Surface.Parameter → List Static.TraitMethodParameter → Prop where
  | nil : TraitMethodParametersRetain context [] []
  | named
      (type : TypeRetains context surfaceType retainedType)
      (tail : TraitMethodParametersRetain context surfaceTail retainedTail) :
      TraitMethodParametersRetain context (.named name surfaceType :: surfaceTail)
        (.named retainedType :: retainedTail)
  | selfValue
      (tail : TraitMethodParametersRetain context surfaceTail retainedTail) :
      TraitMethodParametersRetain context (.selfValue none :: surfaceTail)
        (.receiver .value none :: retainedTail)
  | selfValueTyped
      (type : TypeRetains context surfaceType retainedType)
      (tail : TraitMethodParametersRetain context surfaceTail retainedTail) :
      TraitMethodParametersRetain context (.selfValue (some surfaceType) :: surfaceTail)
        (.receiver .value (some retainedType) :: retainedTail)
  | selfReference
      (tail : TraitMethodParametersRetain context surfaceTail retainedTail) :
      TraitMethodParametersRetain context (.selfReference :: surfaceTail)
        (.receiver .reference none :: retainedTail)

inductive CollectedTraitScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.TraitScheme) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.TraitDecl)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (methodDeclarations : List Nat)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.trait surface))
      (headerKind : header.kind = .trait)
      (schemeMember : scheme ∈ context.traits)
      (declaration : scheme.declaration = header.declaration)
      (visibility : scheme.isPublic = surface.isPublic)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (typeParametersOnly : GenericParametersAreTypes surface.genericParameters)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements)
      (methods : TraitMethodHeaders pack catalog address 0
        surface.methods methodDeclarations)
      (schemeMethods : scheme.methodDeclarations = methodDeclarations) :
      CollectedTraitScheme pack catalog context header scheme

/-- Current Lanius accepts generic syntax on trait methods during parsing but
    rejects method-local generics and method-local `where` clauses during trait
    validation.  The contract relation records that boundary explicitly. -/
inductive CollectedTraitMethodContract
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (parentHeader methodHeader : Declarations.DeclarationHeader)
    (traitScheme : Static.TraitScheme)
    (contract : Static.TraitMethodContract) : Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surfaceTrait : Surface.TraitDecl)
      (surfaceMethod : Surface.TraitMethod)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (retainedParameters : List Static.TraitMethodParameter)
      (retainedReturnType : Static.Ty)
      (parentSource : parentHeader.source = .item parent)
      (parentMember : parentHeader ∈ catalog.headers)
      (parentMatches : Declarations.HeaderMatches pack parentHeader)
      (parentFound : pack.item? parent = some (.trait surfaceTrait))
      (parentKind : parentHeader.kind = .trait)
      (methodSource : methodHeader.source = .traitMethod parent index)
      (methodMember : methodHeader ∈ catalog.headers)
      (methodMatches : Declarations.HeaderMatches pack methodHeader)
      (methodFound : surfaceTrait.methods[index]? = some surfaceMethod)
      (methodKind : methodHeader.kind = .traitMethod)
      (traitMember : traitScheme ∈ context.traits)
      (traitDeclaration : traitScheme.declaration = parentHeader.declaration)
      (parametersCollected : GenericParametersLower
        (context.forModule parentHeader.moduleId) 0 0
        surfaceTrait.genericParameters genericParameters finalType finalConst)
      (schemeParameters : traitScheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (methodGenericsUnsupported :
        surfaceMethod.signature.genericParameters = [])
      (methodWhereUnsupported : surfaceMethod.signature.wherePredicates = [])
      (parameters : TraitMethodParametersRetain
        (withGenericParameters (context.forModule parentHeader.moduleId)
          genericParameters)
        surfaceMethod.signature.parameters retainedParameters)
      (returned : ReturnTypeRetains
        (withGenericParameters (context.forModule parentHeader.moduleId)
          genericParameters)
        surfaceMethod.signature.name surfaceMethod.signature.returnType retainedReturnType)
      (contractMember : contract ∈ context.traitMethods)
      (contractTrait : contract.trait = traitScheme.trait)
      (contractDeclaration : contract.declaration = methodHeader.declaration)
      (contractName : contract.name = surfaceMethod.signature.name)
      (contractVisibility : contract.isPublic = surfaceMethod.signature.isPublic)
      (contractParameters : contract.parameters = retainedParameters)
      (contractReturnType : contract.returnType = retainedReturnType) :
      CollectedTraitMethodContract pack catalog context parentHeader methodHeader
        traitScheme contract

inductive ImplTraitRetains (context : SurfaceElaboration.Context)
    (receiver : Static.Ty) :
    Option Surface.TypeExpr → Option Static.TraitPattern →
      Option Static.TraitScheme → Prop where
  | inherent : ImplTraitRetains context receiver none none none
  | trait
      (selected : SelectsTrait context { segments } trait)
      (argumentsFound : SurfaceElaboration.pathTypeArguments? { segments } =
        some surfaceArguments)
      (arguments : TypesRetain context surfaceArguments retainedArguments) :
      ImplTraitRetains context receiver (some (.path segments))
        (some { trait := trait.trait, receiver, arguments := retainedArguments })
        (some trait)

inductive ImplementationMethodHeaders
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (parent : Declarations.ItemAddress) :
    Nat → List Surface.Function → List Nat → Prop where
  | nil : ImplementationMethodHeaders pack catalog parent index [] []
  | cons
      (header : Declarations.DeclarationHeader)
      (member : header ∈ catalog.headers)
      (source : header.source = .implementationMethod parent index)
      (kind : header.kind = .implementationMethod)
      (headerValid : Declarations.HeaderMatches pack header)
      (tail : ImplementationMethodHeaders pack catalog parent (index + 1)
        surfaceTail declarationTail) :
      ImplementationMethodHeaders pack catalog parent index
        (surfaceHead :: surfaceTail) (header.declaration :: declarationTail)

inductive CollectedImplScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.ImplScheme) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.ImplDecl)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (receiver : Static.Ty)
      (implementedTrait : Option Static.TraitPattern)
      (selectedTrait : Option Static.TraitScheme)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (methodDeclarations : List Nat)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.implementation surface))
      (headerKind : header.kind = .implementation)
      (schemeMember : scheme ∈ context.implementations)
      (declaration : scheme.declaration = header.declaration)
      (visibility : scheme.isPublic = surface.isPublic)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (receiverType : TypeRetains
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.receiverType receiver)
      (schemeReceiver : scheme.receiver = receiver)
      (traitType : ImplTraitRetains
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        receiver surface.traitType implementedTrait selectedTrait)
      (schemeTrait : scheme.implementedTrait = implementedTrait)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements)
      (traitVisibility : match selectedTrait with
        | none => True
        | some trait => Static.TraitImplVisibilityMatches trait scheme)
      (methods : ImplementationMethodHeaders pack catalog address 0
        surface.methods methodDeclarations)
      (schemeMethods : scheme.methodDeclarations = methodDeclarations) :
      CollectedImplScheme pack catalog context header scheme

/-- An implementation receiver depends only on the implementation's declared
    generic parameters. Agreement on that domain makes receiver substitution
    functional even when a caller carries additional method-local bindings. -/
theorem CollectedImplScheme.receiver_substitute_eq_of_parameter_agreement
    (collected : CollectedImplScheme pack catalog context header scheme)
    (typeAgreement : ∀ parameter,
      .typeParameter parameter ∈ scheme.genericParameters →
        leftSubstitution.types parameter = rightSubstitution.types parameter)
    (constAgreement : ∀ parameter,
      .constParameter parameter ∈ scheme.genericParameters →
        leftSubstitution.constants parameter =
          rightSubstitution.constants parameter) :
    scheme.receiver.substitute leftSubstitution =
      scheme.receiver.substitute rightSubstitution := by
  cases collected with
  | intro address surface genericParameters receiver implementedTrait
      selectedTrait genericRequirements whereRequirements methodDeclarations
      source headerMember headerMatches itemFound headerKind schemeMember
      declaration visibility namesUnique parametersCollected schemeParameters
      receiverType schemeReceiver traitType schemeTrait genericBounds
      whereBounds schemeRequirements traitVisibility methods schemeMethods =>
      rw [schemeReceiver]
      exact receiverType.substitute_eq_of_parameter_agreement
        (fun parameter member => typeAgreement parameter (by
          rw [schemeParameters]
          exact member))
        (fun parameter member => constAgreement parameter (by
          rw [schemeParameters]
          exact member))

inductive ImplementationMethodParametersRetain
    (context : SurfaceElaboration.Context) (receiver : Static.Ty) :
    List Surface.Parameter → List Static.Ty → Prop where
  | nil : ImplementationMethodParametersRetain context receiver [] []
  | named
      (type : TypeRetains context surfaceType retainedType)
      (tail : ImplementationMethodParametersRetain context receiver
        surfaceTail retainedTail) :
      ImplementationMethodParametersRetain context receiver
        (.named name surfaceType :: surfaceTail) (retainedType :: retainedTail)
  | selfValue
      (tail : ImplementationMethodParametersRetain context receiver
        surfaceTail retainedTail) :
      ImplementationMethodParametersRetain context receiver
        (.selfValue none :: surfaceTail) (receiver :: retainedTail)
  | selfValueTyped
      (type : TypeRetains context surfaceType receiver)
      (tail : ImplementationMethodParametersRetain context receiver
        surfaceTail retainedTail) :
      ImplementationMethodParametersRetain context receiver
        (.selfValue (some surfaceType) :: surfaceTail) (receiver :: retainedTail)
  | selfReference
      (tail : ImplementationMethodParametersRetain context receiver
        surfaceTail retainedTail) :
      ImplementationMethodParametersRetain context receiver
        (.selfReference :: surfaceTail) (.reference receiver :: retainedTail)

def SelectsTraitMethodContract
    (context : SurfaceElaboration.Context)
    (trait : Static.TraitScheme)
    (pattern : Static.TraitPattern)
    (name : Surface.Name)
    (parameterTypes : List Static.Ty)
    (returnType : Static.Ty)
    (selected : Static.TraitMethodContract) : Prop :=
  selected ∈ context.traitMethods ∧
    selected.trait = trait.trait ∧
    selected.name = name ∧
    Static.TraitMethodContractSpecializes trait pattern selected
      parameterTypes returnType ∧
    ∀ candidate,
      candidate ∈ context.traitMethods →
      candidate.trait = trait.trait →
      candidate.name = name →
      Static.TraitMethodContractSpecializes trait pattern candidate
        parameterTypes returnType →
      candidate.declaration = selected.declaration

inductive CollectedTraitImplementationMethodConforms
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (parentHeader methodHeader : Declarations.DeclarationHeader)
    (implementation : Static.ImplScheme)
    (contract : Static.TraitMethodContract) :
    SurfaceElaboration.Context → List Static.Ty → Static.Ty → Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surfaceImpl : Surface.ImplDecl)
      (surfaceMethod : Surface.Function)
      (implParameters : List SurfaceElaboration.TypeAliasParameter)
      (pattern : Static.TraitPattern)
      (trait : Static.TraitScheme)
      (parameterTypes : List Static.Ty)
      (returnType : Static.Ty)
      (parentSource : parentHeader.source = .item parent)
      (parentFound : pack.item? parent = some (.implementation surfaceImpl))
      (implementationCollected : CollectedImplScheme pack catalog context
        parentHeader implementation)
      (implements : implementation.implementedTrait = some pattern)
      (traitMember : trait ∈ context.traits)
      (traitIdentity : trait.trait = pattern.trait)
      (methodSource : methodHeader.source = .implementationMethod parent index)
      (methodMember : methodHeader ∈ catalog.headers)
      (methodMatches : Declarations.HeaderMatches pack methodHeader)
      (methodFound : surfaceImpl.methods[index]? = some surfaceMethod)
      (methodKind : methodHeader.kind = .implementationMethod)
      (implParametersCollected : GenericParametersLower
        (context.forModule parentHeader.moduleId) 0 0
        surfaceImpl.genericParameters implParameters finalType finalConst)
      (implementationParameters : implementation.genericParameters =
        implParameters.map aliasParameterToStatic)
      (methodGenericsUnsupported : surfaceMethod.genericParameters = [])
      (methodWhereUnsupported : surfaceMethod.wherePredicates = [])
      (parameters : ImplementationMethodParametersRetain
        (withGenericParameters (context.forModule parentHeader.moduleId) implParameters)
        implementation.receiver
        surfaceMethod.parameters parameterTypes)
      (returned : ReturnTypeRetains
        (withGenericParameters (context.forModule parentHeader.moduleId) implParameters)
        surfaceMethod.name surfaceMethod.returnType returnType)
      (selected : SelectsTraitMethodContract context trait pattern
        surfaceMethod.name parameterTypes returnType contract)
      (visibility : contract.isPublic = surfaceMethod.isPublic)
      (bodyScoped : SourceWellFormed.FunctionBodyWellScoped
        (context.forModule parentHeader.moduleId)
        surfaceMethod.parameters surfaceMethod.body)
      (bodyTyped : FunctionBodySymbolicallyTyped
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters)
        implementation.requirements surfaceMethod.parameters parameterTypes
        returnType surfaceMethod.body) :
      CollectedTraitImplementationMethodConforms pack catalog context
        parentHeader methodHeader implementation contract
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters) parameterTypes returnType

def TraitImplementationConforms
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (parentHeader : Declarations.DeclarationHeader)
    (implementation : Static.ImplScheme) : Prop :=
  (∀ methodHeader, methodHeader ∈ catalog.headers →
    ∀ parent index,
      methodHeader.source = .implementationMethod parent index →
      parentHeader.source = .item parent →
      ∃ contract bodyContext parameterTypes returnType,
        CollectedTraitImplementationMethodConforms pack catalog context
          parentHeader methodHeader implementation contract bodyContext
          parameterTypes returnType) ∧
  ∀ pattern trait contract,
    implementation.implementedTrait = some pattern →
    trait ∈ context.traits → trait.trait = pattern.trait →
    contract ∈ context.traitMethods → contract.trait = trait.trait →
    contract.declaration ∈ trait.methodDeclarations →
    ∃ methodHeader bodyContext parameterTypes returnType,
      methodHeader ∈ catalog.headers ∧
      CollectedTraitImplementationMethodConforms pack catalog context
        parentHeader methodHeader implementation contract bodyContext
        parameterTypes returnType

/-- A demanded trait-implementation method body specializes the exact symbolic
    parameter and return types selected by trait-contract conformance. The
    ground implementation goal, parameter allocation, statement tree, and
    emitted function are retained in the same derivation. -/
inductive TraitImplementationMethodSpecializes
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.Function)
    (implementation : Static.ImplScheme)
    (methodHeader : Declarations.DeclarationHeader)
    (symbolicParameterTypes : List Static.Ty)
    (symbolicReturnType : Static.Ty)
    (resolved : Static.TraitImplementationMethodInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (pattern : Static.TraitPattern)
      (goal : Static.TraitGoal)
      (parametersBound : Static.ParametersBound substitution
        implementation.genericParameters)
      (implements : implementation.implementedTrait = some pattern)
      (goalInstantiated : pattern.instantiate substitution = some goal)
      (requirements : Static.RequirementsSatisfied baseContext.implementations
        substitution implementation.requirements)
      (instanceMember : resolved ∈
        baseContext.traitImplementationMethodInstances)
      (instanceImplementation : resolved.implementation = implementation.id)
      (instanceDeclaration : resolved.declaration = methodHeader.declaration)
      (symbolicBindings : List SymbolicLocalBinding)
      (symbolicParameters : SymbolicParametersBind surface.parameters
        symbolicParameterTypes symbolicBindings)
      (initialContexts : ({
          globals := baseContext
          assumptions := implementation.requirements
          returnType := symbolicReturnType
          locals := []
        } : SymbolicBodyContext).Specializes substitution resolved.returnType
          { baseContext with substitution })
      (parameterTypesGround : Static.instantiateTypes substitution
        symbolicParameterTypes = some resolved.parameterTypes)
      (coreParameters : List (VarId × Core.Ty))
      (bodyContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (parameters : ParametersLower { baseContext with substitution }
        (some goal.receiver) 0 surface.parameters resolved.parameterTypes
        coreParameters bodyContext nextLocal)
      (returnRetained : ReturnTypeRetains baseContext surface.name
        surface.returnType symbolicReturnType)
      (coreReturnType : Core.Ty)
      (returnTypeCore : resolved.returnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (coreBody : Core.Stmt)
      (finalLocal : VarId)
      (body : StmtsSpecialize substitution resolved.returnType {
          globals := baseContext
          assumptions := implementation.requirements
          returnType := symbolicReturnType
          locals := symbolicBindings
        } bodyContext nextLocal false surface.body coreBody finalLocal)
      (definition : core = {
        id := resolved.function
        parameters := coreParameters
        returnType := coreReturnType
        body := some coreBody
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      TraitImplementationMethodSpecializes program baseContext surface
        implementation methodHeader symbolicParameterTypes symbolicReturnType
        resolved core

theorem TraitImplementationMethodSpecializes.symbolic
    (specialized : TraitImplementationMethodSpecializes program baseContext
      surface implementation methodHeader symbolicParameterTypes
      symbolicReturnType resolved core) :
    FunctionBodySymbolicallyTyped baseContext implementation.requirements
      surface.parameters symbolicParameterTypes symbolicReturnType surface.body := by
  cases specialized with
  | intro substitution pattern goal parametersBound implements goalInstantiated
      requirements instanceMember instanceImplementation instanceDeclaration
      symbolicBindings symbolicParameters initialContexts parameterTypesGround
      coreParameters bodyContext nextLocal parameters returnRetained
      coreReturnType returnTypeCore coreBody finalLocal body definition target
      member typed =>
      exact ⟨symbolicBindings, symbolicParameters, body.symbolic⟩

theorem TraitImplementationMethodSpecializes.instanceTypes
    (specialized : TraitImplementationMethodSpecializes program baseContext
      surface implementation methodHeader symbolicParameterTypes
      symbolicReturnType resolved core) :
    ∃ substitution,
      Static.instantiateTypes substitution symbolicParameterTypes =
        some resolved.parameterTypes ∧
      symbolicReturnType.instantiate substitution = some resolved.returnType := by
  cases specialized with
  | intro substitution pattern goal parametersBound implements goalInstantiated
      requirements instanceMember instanceImplementation instanceDeclaration
      symbolicBindings symbolicParameters initialContexts parameterTypesGround
      coreParameters bodyContext nextLocal parameters returnRetained
      coreReturnType returnTypeCore coreBody finalLocal body definition target
      member typed =>
      exact ⟨substitution, parameterTypesGround, initialContexts.returnType⟩

theorem TraitImplementationMethodSpecializes.parameterContexts
    (specialized : TraitImplementationMethodSpecializes program baseContext
      surface implementation methodHeader symbolicParameterTypes
      symbolicReturnType resolved core) :
    ∃ substitution symbolicBindings bodyContext,
      ({
        globals := baseContext
        assumptions := implementation.requirements
        returnType := symbolicReturnType
        locals := symbolicBindings
      } : SymbolicBodyContext).Specializes substitution resolved.returnType
        bodyContext := by
  cases specialized with
  | intro substitution pattern goal parametersBound implements goalInstantiated
      requirements instanceMember instanceImplementation instanceDeclaration
      actualBindings symbolicParameters initialContexts parameterTypesGround
      coreParameters bodyContext nextLocal parameters returnRetained
      coreReturnType returnTypeCore coreBody finalLocal body definition target
      member typed =>
      have parameterContexts := symbolicParameters.specializes initialContexts
        parameterTypesGround parameters
      have baseLocals : baseContext.locals = [] :=
        initialContexts.locals.concrete_eq_nil
      exact ⟨substitution, actualBindings, bodyContext, by
        simpa [SymbolicBodyContext.bindMany_eq, baseLocals] using
          parameterContexts⟩

/-- Complete trait-method artifacts retain both source-contract conformance and
    the coupled specialization of that exact source occurrence. -/
inductive TraitImplementationMethodFunctionLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (parentHeader methodHeader : Declarations.DeclarationHeader)
    (implementation : Static.ImplScheme)
    (contract : Static.TraitMethodContract)
    (resolved : Static.TraitImplementationMethodInstance)
    (core : Core.Function) : Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surfaceImpl : Surface.ImplDecl)
      (surfaceMethod : Surface.Function)
      (symbolicContext : SurfaceElaboration.Context)
      (symbolicParameterTypes : List Static.Ty)
      (symbolicReturnType : Static.Ty)
      (parentSource : parentHeader.source = .item parent)
      (parentFound : pack.item? parent = some (.implementation surfaceImpl))
      (methodSource : methodHeader.source = .implementationMethod parent index)
      (methodFound : surfaceImpl.methods[index]? = some surfaceMethod)
      (conforms : CollectedTraitImplementationMethodConforms pack catalog
        baseContext parentHeader methodHeader implementation contract
        symbolicContext symbolicParameterTypes symbolicReturnType)
      (specializes : TraitImplementationMethodSpecializes program symbolicContext
        surfaceMethod implementation methodHeader symbolicParameterTypes
        symbolicReturnType resolved core) :
      TraitImplementationMethodFunctionLowers pack catalog program baseContext
        parentHeader methodHeader implementation contract resolved core

/-- Classify an inherent implementation function after type retention. A
    receiverless function, or a function whose ordinary first parameter is not
    the implementation receiver, is associated-only. `self`, `&self`, and an
    ordinary first parameter equal to the receiver retain the three callable
    receiver modes used by member and associated lookup. -/
inductive InherentMethodParametersRetain
    (context : SurfaceElaboration.Context) (receiver : Static.Ty) :
    List Surface.Parameter → Static.ReceiverMode → List Static.Ty → Prop where
  | named
      (receiverType : TypeRetains context surfaceReceiver receiver)
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      InherentMethodParametersRetain context receiver
        (.named receiverName surfaceReceiver :: surfaceTail) .explicit retainedTail
  | associatedNil :
      InherentMethodParametersRetain context receiver [] .none []
  | associatedNamed
      (notReceiver : ¬ TypeRetains context surfaceFirst receiver)
      (first : TypeRetains context surfaceFirst retainedFirst)
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      InherentMethodParametersRetain context receiver
        (.named firstName surfaceFirst :: surfaceTail) .none
        (retainedFirst :: retainedTail)
  | selfValue
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      InherentMethodParametersRetain context receiver
        (.selfValue none :: surfaceTail) .value retainedTail
  | selfValueTyped
      (receiverType : TypeRetains context surfaceReceiver receiver)
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      InherentMethodParametersRetain context receiver
        (.selfValue (some surfaceReceiver) :: surfaceTail) .value retainedTail
  | selfReference
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      InherentMethodParametersRetain context receiver
        (.selfReference :: surfaceTail) .reference retainedTail

/-- Receiver syntax does not enter the ordinary argument vector. Every
    retained non-receiver method parameter therefore inherits declaration-
    domain substitution functionality from `ParameterTypesRetain`. -/
theorem InherentMethodParametersRetain.arguments_substitute_eq_of_arguments
    (retained : InherentMethodParametersRetain
      (withGenericParameters baseContext declaredParameters) receiver
      surfaceParameters receiverMode argumentTypes)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments) :
    Static.substituteTypes leftSubstitution argumentTypes =
      Static.substituteTypes rightSubstitution argumentTypes := by
  cases retained with
  | named _ tail => exact tail.substitute_eq_of_arguments leftBound rightBound
  | associatedNil => rfl
  | associatedNamed _ first tail =>
      simp [Static.substituteTypes,
        first.substitute_eq_of_arguments leftBound rightBound,
        tail.substitute_eq_of_arguments leftBound rightBound]
  | selfValue tail => exact tail.substitute_eq_of_arguments leftBound rightBound
  | selfValueTyped _ tail =>
      exact tail.substitute_eq_of_arguments leftBound rightBound
  | selfReference tail =>
      exact tail.substitute_eq_of_arguments leftBound rightBound

inductive CollectedInherentMethodScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (parentHeader methodHeader : Declarations.DeclarationHeader)
    (implementation : Static.ImplScheme)
    (scheme : Static.MethodScheme) :
    SurfaceElaboration.Context → Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surfaceImpl : Surface.ImplDecl)
      (surfaceMethod : Surface.Function)
      (implParameters : List SurfaceElaboration.TypeAliasParameter)
      (receiverMode : Static.ReceiverMode)
      (argumentTypes : List Static.Ty)
      (returnType : Static.Ty)
      (parentSource : parentHeader.source = .item parent)
      (parentMember : parentHeader ∈ catalog.headers)
      (parentMatches : Declarations.HeaderMatches pack parentHeader)
      (parentFound : pack.item? parent = some (.implementation surfaceImpl))
      (parentKind : parentHeader.kind = .implementation)
      (implementationCollected : CollectedImplScheme pack catalog context
        parentHeader implementation)
      (inherent : implementation.implementedTrait = none)
      (methodSource : methodHeader.source = .implementationMethod parent index)
      (methodMember : methodHeader ∈ catalog.headers)
      (methodMatches : Declarations.HeaderMatches pack methodHeader)
      (methodFound : surfaceImpl.methods[index]? = some surfaceMethod)
      (methodKind : methodHeader.kind = .implementationMethod)
      (implParametersCollected : GenericParametersLower
        (context.forModule parentHeader.moduleId) 0 0
        surfaceImpl.genericParameters implParameters implFinalType implFinalConst)
      (implementationParameters : implementation.genericParameters =
        implParameters.map aliasParameterToStatic)
      (methodGenericsUnsupported : surfaceMethod.genericParameters = [])
      (methodWhereUnsupported : surfaceMethod.wherePredicates = [])
      (parameters : InherentMethodParametersRetain
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters)
        implementation.receiver surfaceMethod.parameters receiverMode argumentTypes)
      (returned : ReturnTypeRetains
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters)
        surfaceMethod.name surfaceMethod.returnType returnType)
      (schemeMember : scheme ∈ context.methods)
      (schemeName : scheme.name = surfaceMethod.name)
      (schemeDeclaration : scheme.declaration = methodHeader.declaration)
      (schemeModule : scheme.moduleId = parentHeader.moduleId)
      (schemeVisibility : scheme.isPublic = surfaceMethod.isPublic)
      (schemeReceiverMode : scheme.receiverMode = receiverMode)
      (schemeReceiver : scheme.receiverType = implementation.receiver)
      (schemeArguments : scheme.argumentTypes = argumentTypes)
      (schemeReturn : scheme.returnType = returnType)
      (schemeParameters : scheme.genericParameters = implementation.genericParameters)
      (schemeRequirements : scheme.requirements = implementation.requirements)
      (bodyScoped : SourceWellFormed.FunctionBodyWellScoped
        (context.forModule parentHeader.moduleId)
        surfaceMethod.parameters surfaceMethod.body)
      (bodyTyped : FunctionBodySymbolicallyTyped
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters)
        scheme.requirements surfaceMethod.parameters
        (symbolicMethodParameterTypes scheme) scheme.returnType
        surfaceMethod.body) :
      CollectedInherentMethodScheme pack catalog context parentHeader methodHeader
        implementation scheme
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters)

/-- Every accepted inherent method is traced back to source syntax whose
    method-local generic and `where` lists are empty. Enclosing implementation
    generics are unaffected. -/
theorem CollectedInherentMethodScheme.source_restrictions
    (collected : CollectedInherentMethodScheme pack catalog context parentHeader
      methodHeader implementation scheme bodyContext) :
    ∃ parent index surfaceImpl surfaceMethod,
      parentHeader.source = .item parent ∧
      pack.item? parent = some (.implementation surfaceImpl) ∧
      methodHeader.source = .implementationMethod parent index ∧
      surfaceImpl.methods[index]? = some surfaceMethod ∧
      surfaceMethod.genericParameters = [] ∧
      surfaceMethod.wherePredicates = [] := by
  cases collected with
  | intro parent index surfaceImpl surfaceMethod implParameters
      receiverMode argumentTypes returnType parentSource parentMember parentMatches
      parentFound parentKind implementationCollected inherent methodSource
      methodMember methodMatches methodFound methodKind implParametersCollected
      implementationParameters methodGenericsUnsupported methodWhereUnsupported
      parameters returned schemeMember schemeName schemeDeclaration schemeModule
      schemeVisibility schemeReceiverMode schemeReceiver schemeArguments schemeReturn
      schemeParameters schemeRequirements bodyScoped bodyTyped =>
      exact ⟨parent, index, surfaceImpl, surfaceMethod, parentSource, parentFound,
        methodSource, methodFound, methodGenericsUnsupported,
        methodWhereUnsupported⟩

/-- A collected inherent method signature observes only the implementation's
    ordered generic argument vector. The current compiler parses but rejects
    method-local generic parameters and predicates. -/
theorem CollectedInherentMethodScheme.signature_substitute_unique
    (collected : CollectedInherentMethodScheme pack catalog context parentHeader
      methodHeader implementation scheme bodyContext)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      scheme.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      scheme.genericParameters typeArguments constArguments)
    (leftReceiver : scheme.receiverType.substitute leftSubstitution =
      some leftReceiverType)
    (rightReceiver : scheme.receiverType.substitute rightSubstitution =
      some rightReceiverType)
    (leftArguments : Static.substituteTypes leftSubstitution
      scheme.argumentTypes = some leftArgumentTypes)
    (rightArguments : Static.substituteTypes rightSubstitution
      scheme.argumentTypes = some rightArgumentTypes)
    (leftReturn : scheme.returnType.substitute leftSubstitution =
      some leftReturnType)
    (rightReturn : scheme.returnType.substitute rightSubstitution =
      some rightReturnType) :
    leftReceiverType = rightReceiverType ∧
      leftArgumentTypes = rightArgumentTypes ∧
      leftReturnType = rightReturnType := by
  cases collected with
  | intro parent index surfaceImpl surfaceMethod implParameters
      receiverMode argumentTypes returnType parentSource parentMember parentMatches parentFound
      parentKind implementationCollected inherent methodSource methodMember
      methodMatches methodFound methodKind implParametersCollected
      implementationParameters methodGenericsUnsupported methodWhereUnsupported
      parameters returned
      schemeMember schemeName schemeDeclaration schemeModule schemeVisibility
      schemeReceiverMode schemeReceiver schemeArguments schemeReturn
      schemeParameters schemeRequirements bodyScoped bodyTyped =>
      have receiverEquality :=
        implementationCollected.receiver_substitute_eq_of_parameter_agreement
          (fun parameter member => leftBound.type_agrees rightBound (by
            rw [schemeParameters]
            exact member))
          (fun parameter member => leftBound.const_agrees rightBound (by
            rw [schemeParameters]
            exact member))
      rw [schemeReceiver] at leftReceiver rightReceiver
      rw [leftReceiver, rightReceiver] at receiverEquality
      have concreteReceiverEquality := Option.some.inj receiverEquality
      rw [schemeParameters, implementationParameters] at leftBound rightBound
      rw [schemeArguments] at leftArguments rightArguments
      rw [schemeReturn] at leftReturn rightReturn
      have argumentEquality :=
        parameters.arguments_substitute_eq_of_arguments leftBound rightBound
      have returnEquality :=
        returned.substitute_eq_of_arguments leftBound rightBound
      rw [leftArguments, rightArguments] at argumentEquality
      rw [leftReturn, rightReturn] at returnEquality
      exact ⟨concreteReceiverEquality, Option.some.inj argumentEquality,
        Option.some.inj returnEquality⟩

def methodGroundParameterTypes (resolved : Static.MethodInstance) :
    List Static.GroundTy :=
  match resolved.receiverMode with
  | .none => resolved.argumentTypes
  | .value | .explicit => resolved.receiverType :: resolved.argumentTypes
  | .reference => .reference resolved.receiverType :: resolved.argumentTypes

def methodReceiverType? (resolved : Static.MethodInstance) :
    Option Static.GroundTy :=
  match resolved.receiverMode with
  | .none => none
  | .value | .reference | .explicit => some resolved.receiverType

theorem methodInstantiationParameterTypes
    (instantiated : Static.MethodInstantiates implementations scheme substitution
      resolved) :
    Static.instantiateTypes substitution (symbolicMethodParameterTypes scheme) =
      some (methodGroundParameterTypes resolved) := by
  obtain ⟨receiverGrounds, argumentGrounds, returnGrounds, declaration,
    name, mode⟩ := instantiated.signature
  cases schemeMode : scheme.receiverMode with
  | none =>
      rw [schemeMode] at mode
      simp [symbolicMethodParameterTypes, methodGroundParameterTypes, schemeMode,
        mode, Static.instantiateTypes, argumentGrounds]
  | value =>
      rw [schemeMode] at mode
      simp [symbolicMethodParameterTypes, methodGroundParameterTypes, schemeMode,
        mode, Static.instantiateTypes, receiverGrounds, argumentGrounds]
  | reference =>
      rw [schemeMode] at mode
      simp [symbolicMethodParameterTypes, methodGroundParameterTypes, schemeMode,
        mode, Static.instantiateTypes, Static.Ty.instantiate, receiverGrounds,
        argumentGrounds]
  | explicit =>
      rw [schemeMode] at mode
      simp [symbolicMethodParameterTypes, methodGroundParameterTypes, schemeMode,
        mode, Static.instantiateTypes, receiverGrounds, argumentGrounds]

inductive MethodFunctionLowers
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.Function)
    (scheme : Static.MethodScheme)
    (monomorphicInstance : Static.MethodInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (groundParameters : List Static.GroundTy)
      (coreParameters : List (VarId × Core.Ty))
      (bodyContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (groundReturnType : Static.GroundTy)
      (coreReturnType : Core.Ty)
      (coreBody : Core.Stmt)
      (finalLocal : VarId)
      (instantiated : Static.MethodInstantiates baseContext.implementations
        scheme substitution monomorphicInstance)
      (parameters : ParametersLower { baseContext with substitution := substitution }
        (methodReceiverType? monomorphicInstance) 0 surface.parameters groundParameters
        coreParameters bodyContext nextLocal)
      (parameterTypes : groundParameters =
        methodGroundParameterTypes monomorphicInstance)
      (returned : ReturnTypeGrounds { baseContext with substitution := substitution }
        surface.name surface.returnType groundReturnType)
      (selectedReturnType : groundReturnType = monomorphicInstance.returnType)
      (returnTypeCore : groundReturnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (body : SurfaceElaboration.StmtsLower bodyContext nextLocal surface.body
        coreBody finalLocal)
      (definition : core = {
        id := monomorphicInstance.function
        parameters := coreParameters
        returnType := coreReturnType
        body := some coreBody
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      MethodFunctionLowers program baseContext surface scheme monomorphicInstance core

/-- One finite inherent-method artifact specializes the exact generic body
    context collected for its declaration. Receiver adaptation, dense parameter
    allocation, symbolic typing, concrete lowering, and the emitted core row
    are therefore one derivation rather than independently chosen witnesses. -/
inductive MethodSpecializes
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.Function)
    (scheme : Static.MethodScheme)
    (resolved : Static.MethodInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (instantiated : Static.MethodInstantiates baseContext.implementations
        scheme substitution resolved)
      (baseLocals : baseContext.locals = [])
      (symbolicBindings : List SymbolicLocalBinding)
      (symbolicParameters : SymbolicParametersBind surface.parameters
        (symbolicMethodParameterTypes scheme) symbolicBindings)
      (coreParameters : List (VarId × Core.Ty))
      (bodyContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (parameters : ParametersLower { baseContext with substitution }
        (methodReceiverType? resolved) 0 surface.parameters
        (methodGroundParameterTypes resolved) coreParameters bodyContext nextLocal)
      (returnRetained : ReturnTypeRetains baseContext surface.name
        surface.returnType scheme.returnType)
      (coreReturnType : Core.Ty)
      (returnTypeCore : resolved.returnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (coreBody : Core.Stmt)
      (finalLocal : VarId)
      (body : StmtsSpecialize substitution resolved.returnType {
          globals := baseContext
          assumptions := scheme.requirements
          returnType := scheme.returnType
          locals := symbolicBindings
        } bodyContext nextLocal false surface.body coreBody finalLocal)
      (definition : core = {
        id := resolved.function
        parameters := coreParameters
        returnType := coreReturnType
        body := some coreBody
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      MethodSpecializes program baseContext surface scheme resolved core

theorem MethodSpecializes.symbolic
    (specialized : MethodSpecializes program baseContext surface scheme
      resolved core) :
    FunctionBodySymbolicallyTyped baseContext scheme.requirements
      surface.parameters (symbolicMethodParameterTypes scheme)
      scheme.returnType surface.body := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      exact ⟨symbolicBindings, symbolicParameters, body.symbolic⟩

theorem MethodSpecializes.lowers
    (specialized : MethodSpecializes program baseContext surface scheme
      resolved core) :
    MethodFunctionLowers program baseContext surface scheme resolved core := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      have signature := instantiated.signature
      have initialContexts := SymbolicBodyContext.declarationSpecializes
        baseContext scheme.requirements scheme.returnType substitution
        resolved.returnType baseLocals signature.2.2.1
      apply MethodFunctionLowers.intro
          (substitution := substitution)
          (groundParameters := methodGroundParameterTypes resolved)
          (coreParameters := coreParameters)
          (bodyContext := bodyContext)
          (nextLocal := nextLocal)
          (groundReturnType := resolved.returnType)
          (coreReturnType := coreReturnType)
          (coreBody := coreBody)
          (finalLocal := finalLocal)
      · exact instantiated
      · exact parameters
      · rfl
      · exact returnRetained.specializes initialContexts signature.2.2.1
      · rfl
      · exact returnTypeCore
      · exact body.lowers
      · exact definition
      · exact target
      · exact member
      · exact typed

theorem MethodSpecializes.instanceTypes
    (specialized : MethodSpecializes program baseContext surface scheme
      resolved core) :
    ∃ substitution,
      scheme.receiverType.instantiate substitution = some resolved.receiverType ∧
      Static.instantiateTypes substitution scheme.argumentTypes =
        some resolved.argumentTypes ∧
      scheme.returnType.instantiate substitution = some resolved.returnType := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      exact ⟨substitution, instantiated.signature.1,
        instantiated.signature.2.1, instantiated.signature.2.2.1⟩

theorem MethodSpecializes.parameterContexts
    (specialized : MethodSpecializes program baseContext surface scheme
      resolved core) :
    ∃ substitution symbolicBindings bodyContext,
      ({
        globals := baseContext
        assumptions := scheme.requirements
        returnType := scheme.returnType
        locals := symbolicBindings
      } : SymbolicBodyContext).Specializes substitution resolved.returnType
        bodyContext := by
  cases specialized with
  | intro substitution instantiated baseLocals actualBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters returnRetained
      coreReturnType returnTypeCore coreBody finalLocal body definition target
      member typed =>
      have signature := instantiated.signature
      have initial := SymbolicBodyContext.declarationSpecializes
        baseContext scheme.requirements scheme.returnType substitution
        resolved.returnType baseLocals signature.2.2.1
      have parameterContexts := symbolicParameters.specializes initial
        (methodInstantiationParameterTypes instantiated) parameters
      exact ⟨substitution, actualBindings, bodyContext, by
        simpa [SymbolicBodyContext.bindMany_eq, baseLocals] using
          parameterContexts⟩

inductive CollectedInherentMethodFunctionLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (parentHeader methodHeader : Declarations.DeclarationHeader)
    (implementation : Static.ImplScheme)
    (scheme : Static.MethodScheme)
    (resolved : Static.MethodInstance)
    (core : Core.Function) : Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surfaceImpl : Surface.ImplDecl)
      (surfaceMethod : Surface.Function)
      (bodyContext : SurfaceElaboration.Context)
      (parentSource : parentHeader.source = .item parent)
      (parentFound : pack.item? parent = some (.implementation surfaceImpl))
      (methodSource : methodHeader.source = .implementationMethod parent index)
      (methodFound : surfaceImpl.methods[index]? = some surfaceMethod)
      (schemeCollected : CollectedInherentMethodScheme pack catalog context
        parentHeader methodHeader implementation scheme bodyContext)
      (instanceMember : resolved ∈ context.methodInstances)
      (instanceDeclaration : resolved.declaration = methodHeader.declaration)
      (specializes : MethodSpecializes program bodyContext surfaceMethod scheme
        resolved core) :
      CollectedInherentMethodFunctionLowers pack catalog program context
        parentHeader methodHeader implementation scheme resolved core

inductive EnumVariantHeaders
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (parent : Declarations.ItemAddress) :
    Nat → List Surface.EnumVariant → List Nat → Prop where
  | nil : EnumVariantHeaders pack catalog parent index [] []
  | cons
      (header : Declarations.DeclarationHeader)
      (member : header ∈ catalog.headers)
      (source : header.source = .enumVariant parent index)
      (kind : header.kind = .enumVariant)
      (headerValid : Declarations.HeaderMatches pack header)
      (tail : EnumVariantHeaders pack catalog parent (index + 1)
        surfaceTail declarationTail) :
      EnumVariantHeaders pack catalog parent index (surfaceHead :: surfaceTail)
        (header.declaration :: declarationTail)

def StructFieldNamesUnique (fields : List Surface.StructField) : Prop :=
  fields.Pairwise fun left right => left.name ≠ right.name

def EnumVariantNamesUnique (variants : List Surface.EnumVariant) : Prop :=
  variants.Pairwise fun left right => left.name ≠ right.name

inductive CollectedNominalScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.NominalScheme) : Prop where
  | structureType
      (address : Declarations.ItemAddress)
      (surface : Surface.StructDecl)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.structure surface))
      (headerKind : header.kind = .structureType)
      (schemeMember : scheme ∈ context.nominalSchemes)
      (declaration : scheme.declaration = header.declaration)
      (kind : scheme.kind = .structure)
      (visibility : scheme.isPublic = surface.isPublic)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (fieldNamesUnique : StructFieldNamesUnique surface.fields)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements)
      (noMembers : scheme.memberDeclarations = []) :
      CollectedNominalScheme pack catalog context header scheme
  | enumeration
      (address : Declarations.ItemAddress)
      (surface : Surface.EnumDecl)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (variantDeclarations : List Nat)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.enumeration surface))
      (headerKind : header.kind = .enumeration)
      (schemeMember : scheme ∈ context.nominalSchemes)
      (declaration : scheme.declaration = header.declaration)
      (kind : scheme.kind = .enumeration)
      (visibility : scheme.isPublic = surface.isPublic)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (variantNamesUnique : EnumVariantNamesUnique surface.variants)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements)
      (variants : EnumVariantHeaders pack catalog address 0
        surface.variants variantDeclarations)
      (schemeMembers : scheme.memberDeclarations = variantDeclarations) :
      CollectedNominalScheme pack catalog context header scheme

/-- A struct constructor retains declaration-level field types before
    monomorphization. Field IDs are dense and follow declaration order. -/
inductive StructFieldSchemesRetain
    (context : SurfaceElaboration.Context) :
    FieldId → List Surface.StructField →
      List SurfaceElaboration.StructFieldScheme → Prop where
  | nil : StructFieldSchemesRetain context next [] []
  | cons
      (type : TypeRetains context surfaceField.type retainedType)
      (tail : StructFieldSchemesRetain context (next + 1)
        surfaceTail retainedTail) :
      StructFieldSchemesRetain context next (surfaceField :: surfaceTail)
        ({ name := surfaceField.name, field := next, type := retainedType } ::
          retainedTail)

/-- Every retained struct-field type depends only on the owning declaration's
    ordered generic arguments. Entries outside that parameter domain cannot
    change the substituted field type. -/
theorem StructFieldSchemesRetain.field_substitute_unique
    (retained : StructFieldSchemesRetain
      (withGenericParameters baseContext declaredParameters)
      next surfaceFields retainedFields)
    (member : field ∈ retainedFields)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (leftSubstituted : field.type.substitute leftSubstitution = some leftType)
    (rightSubstituted : field.type.substitute rightSubstitution = some rightType) :
    leftType = rightType := by
  induction retained with
  | nil => simp at member
  | cons retainedType tail induction =>
      simp only [List.mem_cons] at member
      rcases member with rfl | member
      · have equality := retainedType.substitute_eq_of_arguments
          leftBound rightBound
        rw [leftSubstituted, rightSubstituted] at equality
        exact Option.some.inj equality
      · exact induction member

inductive CollectedStructConstructorScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (nominal : Static.NominalScheme)
    (constructor : SurfaceElaboration.StructConstructorScheme) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.StructDecl)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (retainedFields : List SurfaceElaboration.StructFieldScheme)
      (source : header.source = .item address)
      (itemFound : pack.item? address = some (.structure surface))
      (collected : CollectedNominalScheme pack catalog context header nominal)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0 surface.genericParameters
        genericParameters finalType finalConst)
      (nominalParameters : nominal.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (fields : StructFieldSchemesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        0 surface.fields retainedFields)
      (member : constructor ∈ context.structConstructors)
      (constructorDeclaration : constructor.declaration = header.declaration)
      (constructorType : constructor.sourceType = nominal.type)
      (constructorParameters : constructor.genericParameters = nominal.genericParameters)
      (constructorRequirements : constructor.requirements = nominal.requirements)
      (constructorFields : constructor.fields = retainedFields) :
      CollectedStructConstructorScheme pack catalog context header nominal constructor

/-- Collection provenance transfers retained field-type functionality to the
    compact constructor record consumed by expression elaboration. -/
theorem CollectedStructConstructorScheme.field_substitute_unique
    (collected : CollectedStructConstructorScheme pack catalog context header
      nominal constructor)
    (member : field ∈ constructor.fields)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      constructor.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      constructor.genericParameters typeArguments constArguments)
    (leftSubstituted : field.type.substitute leftSubstitution = some leftType)
    (rightSubstituted : field.type.substitute rightSubstitution = some rightType) :
    leftType = rightType := by
  cases collected with
  | intro address surface genericParameters retainedFields source itemFound
      nominalCollected parametersCollected nominalParameters fields
      constructorMember constructorDeclaration constructorType
      constructorParameters constructorRequirements constructorFields =>
      rw [constructorParameters, nominalParameters] at leftBound rightBound
      rw [constructorFields] at member
      exact fields.field_substitute_unique member leftBound rightBound
        leftSubstituted rightSubstituted

/-- Each enum-variant child declaration owns one symbolic constructor row.
    Payload types retain the owning enum's generic parameters. -/
inductive CollectedVariantConstructorScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (parentHeader variantHeader : Declarations.DeclarationHeader)
    (nominal : Static.NominalScheme)
    (constructor : SurfaceElaboration.VariantConstructorScheme) : Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surface : Surface.EnumDecl)
      (variant : Surface.EnumVariant)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (retainedPayload : List Static.Ty)
      (parentSource : parentHeader.source = .item parent)
      (itemFound : pack.item? parent = some (.enumeration surface))
      (variantFound : surface.variants[index]? = some variant)
      (variantMember : variantHeader ∈ catalog.headers)
      (variantSource : variantHeader.source = .enumVariant parent index)
      (variantKind : variantHeader.kind = .enumVariant)
      (variantValid : Declarations.HeaderMatches pack variantHeader)
      (collected : CollectedNominalScheme pack catalog context parentHeader nominal)
      (parametersCollected : GenericParametersLower
        (context.forModule parentHeader.moduleId) 0 0 surface.genericParameters
        genericParameters finalType finalConst)
      (nominalParameters : nominal.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (payload : TypesRetain
        (withGenericParameters (context.forModule parentHeader.moduleId)
          genericParameters)
        variant.payload retainedPayload)
      (member : constructor ∈ context.variantConstructors)
      (constructorDeclaration : constructor.declaration = variantHeader.declaration)
      (constructorNominal : constructor.nominalDeclaration = parentHeader.declaration)
      (constructorType : constructor.sourceType = nominal.type)
      (constructorParameters : constructor.genericParameters = nominal.genericParameters)
      (constructorRequirements : constructor.requirements = nominal.requirements)
      (constructorVariant : constructor.variant = index)
      (constructorPayload : constructor.payload = retainedPayload) :
      CollectedVariantConstructorScheme pack catalog context parentHeader variantHeader
        nominal constructor

/-- A collected enum constructor exposes its child declaration occurrence and
    the declaration ID retained in the constructor metadata row. -/
theorem CollectedVariantConstructorScheme.source_declaration
    (collected : CollectedVariantConstructorScheme pack catalog context
      parentHeader variantHeader nominal constructor) :
    ∃ parent index, variantHeader.source = .enumVariant parent index ∧
      constructor.declaration = variantHeader.declaration := by
  cases collected with
  | intro parent index _surface _variant _genericParameters _retainedPayload
      _parentSource _itemFound _variantFound _variantMember variantSource
      _variantKind _variantValid _collected _parametersCollected
      _nominalParameters _payload _member constructorDeclaration
      _constructorNominal _constructorType _constructorParameters
      _constructorRequirements _constructorVariant _constructorPayload =>
      exact ⟨parent, index, variantSource, constructorDeclaration⟩

/-- A collected enum constructor's payload substitution is functional in its
    ordered receiver arguments. The proof follows payload type names back to
    the owning declaration's generic-parameter scope, so irrelevant entries in
    the two substitution maps cannot affect the result. -/
theorem CollectedVariantConstructorScheme.payload_substitute_unique
    (collected : CollectedVariantConstructorScheme pack catalog context
      parentHeader variantHeader nominal constructor)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      constructor.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      constructor.genericParameters typeArguments constArguments)
    (leftSubstituted : Static.substituteTypes leftSubstitution
      constructor.payload = some leftPayload)
    (rightSubstituted : Static.substituteTypes rightSubstitution
      constructor.payload = some rightPayload) :
    leftPayload = rightPayload := by
  cases collected with
  | intro parent index surface variant genericParameters retainedPayload
      collectedParentSource itemFound variantFound variantMember variantSource
      variantKind variantValid nominalCollected parametersCollected
      nominalParameters payload member constructorDeclaration constructorNominal
      constructorType constructorParameters constructorRequirements
      constructorVariant constructorPayload =>
      rw [constructorParameters, nominalParameters] at leftBound rightBound
      rw [constructorPayload] at leftSubstituted rightSubstituted
      have substitutedEquality :=
        payload.substitute_eq_of_arguments leftBound rightBound
      rw [leftSubstituted, rightSubstituted] at substitutedEquality
      exact Option.some.inj substitutedEquality

inductive StructFieldsGround
    (context : SurfaceElaboration.Context)
    (receiver : Static.GroundTy) :
    FieldId → List Surface.StructField → List Core.Ty → List FieldId → Prop where
  | nil : StructFieldsGround context receiver next [] [] []
  | cons
      (groundType : Static.GroundTy)
      (coreType : Core.Ty)
      (entry : SurfaceElaboration.FieldEntry)
      (entryMember : entry ∈ context.fields)
      (entryReceiver : entry.receiver = receiver)
      (entryName : entry.name = surfaceField.name)
      (entryId : entry.field = next)
      (entryType : entry.type = groundType)
      (type : SurfaceElaboration.TypeGrounds context surfaceField.type groundType)
      (lowered : groundType.toCore context.monomorphization = some coreType)
      (tail : StructFieldsGround context receiver (next + 1)
        surfaceTail coreTail orderTail) :
      StructFieldsGround context receiver next (surfaceField :: surfaceTail)
        (coreType :: coreTail) (next :: orderTail)

inductive MonomorphicStructLowers
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.StructDecl)
    (scheme : Static.NominalScheme)
    (typeArguments : List Static.GroundTy)
    (constArguments : List Nat)
    (core : Core.StructDecl) : Prop where
  | intro
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (substitution : Static.Substitution)
      (coreTypeId : TypeId)
      (coreFields : List Core.Ty)
      (fieldOrder : List FieldId)
      (entry : SurfaceElaboration.StructEntry)
      (parametersCollected : GenericParametersLower baseContext 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (arguments : Static.NominalArgumentsBound substitution
        scheme.genericParameters typeArguments constArguments)
      (requirements : Static.RequirementsSatisfied baseContext.implementations
        substitution scheme.requirements)
      (monomorphized : (Static.GroundTy.nominal scheme.type typeArguments constArguments).toCore
        baseContext.monomorphization = some (.structure coreTypeId))
      (entryMember : entry ∈ baseContext.structures)
      (entryReceiver : entry.receiver =
        .nominal scheme.type typeArguments constArguments)
      (entryCoreType : entry.coreType = coreTypeId)
      (fields : StructFieldsGround
        (withSubstitution (withGenericParameters baseContext genericParameters) substitution)
        (.nominal scheme.type typeArguments constArguments) 0
        surface.fields coreFields fieldOrder)
      (entryOrder : entry.fieldOrder = fieldOrder)
      (definition : core = { id := coreTypeId, fields := coreFields })
      (member : core ∈ program.structures) :
      MonomorphicStructLowers program baseContext surface scheme
        typeArguments constArguments core

inductive CollectedMonomorphicStructLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.NominalScheme)
    (resolved : Static.NominalInstance)
    (core : Core.StructDecl) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.StructDecl)
      (source : header.source = .item address)
      (itemFound : pack.item? address = some (.structure surface))
      (collected : CollectedNominalScheme pack catalog context header scheme)
      (instanceMember : resolved ∈ context.nominalInstances)
      (instanceDeclaration : resolved.declaration = header.declaration)
      (instanceSourceType : resolved.sourceType = scheme.type)
      (instanceKind : resolved.kind = .structure)
      (instanceMapped : Static.NominalInstanceMapped context.monomorphization resolved)
      (coreId : core.id = resolved.coreType)
      (lowers : MonomorphicStructLowers program (context.forModule header.moduleId)
        surface scheme
        resolved.typeArguments resolved.constArguments core) :
      CollectedMonomorphicStructLowers pack catalog program context header scheme
        resolved core

/-- Enum variants occupy a dense, declaration-local `VariantId` domain.  Each
    row is connected to the independently collected child declaration so that
    constructor lookup, payload typing, and core layout cannot disagree about
    which source variant a numeric ID denotes. -/
inductive EnumVariantsGround
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (parent : Declarations.ItemAddress)
    (context : SurfaceElaboration.Context)
    (receiver : Static.GroundTy)
    (coreType : TypeId) :
    VariantId → List Surface.EnumVariant → List (List Core.Ty) → Prop where
  | nil : EnumVariantsGround pack catalog parent context receiver coreType
      next [] []
  | cons
      (header : Declarations.DeclarationHeader)
      (entry : SurfaceElaboration.VariantEntry)
      (groundPayload : List Static.GroundTy)
      (corePayload : List Core.Ty)
      (headerMember : header ∈ catalog.headers)
      (headerSource : header.source = .enumVariant parent next)
      (headerKind : header.kind = .enumVariant)
      (headerValid : Declarations.HeaderMatches pack header)
      (entryMember : entry ∈ context.variants)
      (entryDeclaration : entry.declaration = header.declaration)
      (entryReceiver : entry.receiver = receiver)
      (entryCoreType : entry.coreType = coreType)
      (entryVariant : entry.variant = next)
      (payload : SurfaceElaboration.TypesGround context
        surfaceHead.payload groundPayload)
      (entryPayload : entry.payload = groundPayload)
      (payloadCore : Static.GroundTy.listToCore context.monomorphization
        groundPayload = some corePayload)
      (tail : EnumVariantsGround pack catalog parent context receiver coreType
        (next + 1) surfaceTail coreTail) :
      EnumVariantsGround pack catalog parent context receiver coreType next
        (surfaceHead :: surfaceTail) (corePayload :: coreTail)

inductive MonomorphicEnumLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (address : Declarations.ItemAddress)
    (surface : Surface.EnumDecl)
    (scheme : Static.NominalScheme)
    (typeArguments : List Static.GroundTy)
    (constArguments : List Nat)
    (core : Core.EnumDecl) : Prop where
  | intro
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (substitution : Static.Substitution)
      (coreTypeId : TypeId)
      (coreVariants : List (List Core.Ty))
      (parametersCollected : GenericParametersLower baseContext 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (arguments : Static.NominalArgumentsBound substitution
        scheme.genericParameters typeArguments constArguments)
      (requirements : Static.RequirementsSatisfied baseContext.implementations
        substitution scheme.requirements)
      (monomorphized :
        (Static.GroundTy.nominal scheme.type typeArguments constArguments).toCore
          baseContext.monomorphization = some (.enumeration coreTypeId))
      (itemFound : pack.item? address = some (.enumeration surface))
      (variants : EnumVariantsGround pack catalog address
        (withSubstitution (withGenericParameters baseContext genericParameters)
          substitution)
        (.nominal scheme.type typeArguments constArguments) coreTypeId 0
        surface.variants coreVariants)
      (definition : core = { id := coreTypeId, variants := coreVariants })
      (member : core ∈ program.enumerations) :
      MonomorphicEnumLowers pack catalog program baseContext address surface scheme
        typeArguments constArguments core

inductive CollectedMonomorphicEnumLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.NominalScheme)
    (resolved : Static.NominalInstance)
    (core : Core.EnumDecl) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.EnumDecl)
      (source : header.source = .item address)
      (collected : CollectedNominalScheme pack catalog context header scheme)
      (instanceMember : resolved ∈ context.nominalInstances)
      (instanceDeclaration : resolved.declaration = header.declaration)
      (instanceSourceType : resolved.sourceType = scheme.type)
      (instanceKind : resolved.kind = .enumeration)
      (instanceMapped : Static.NominalInstanceMapped context.monomorphization resolved)
      (coreId : core.id = resolved.coreType)
      (lowers : MonomorphicEnumLowers pack catalog program
        (context.forModule header.moduleId) address surface scheme
        resolved.typeArguments resolved.constArguments core) :
      CollectedMonomorphicEnumLowers pack catalog program context header scheme
        resolved core

/-- An arbitrary ABI name acquires behavior only through an explicit binding.
    Compiler-known host services additionally carry their canonical semantic
    signature, so an ABI table cannot accidentally bind (for example) `exit`
    with the parameter type of `print_i32`. -/
structure ExternalBinding where
  abi : Option String
  name : Surface.Name
  parameterTypes : List Core.Ty
  returnType : Core.Ty
  behavior : Core.ExternalBehavior
deriving DecidableEq, Repr

def ExternalBindingWellFormed (binding : ExternalBinding) : Prop :=
  match binding.behavior with
  | .host service =>
      binding.parameterTypes = service.parameterTypes ∧
        binding.returnType = service.returnType
  | .panic | .unreachable =>
      binding.parameterTypes = [] ∧ binding.returnType = .unit
  | .unavailable _ | .opaque _ => True

def SelectsExternalBinding
    (bindings : List ExternalBinding)
    (abi : Option String)
    (name : Surface.Name)
    (parameterTypes : List Core.Ty)
    (returnType : Core.Ty)
    (selected : ExternalBinding) : Prop :=
  selected ∈ bindings ∧
    selected.abi = abi ∧
    selected.name = name ∧
    selected.parameterTypes = parameterTypes ∧
    selected.returnType = returnType ∧
    ExternalBindingWellFormed selected ∧
    ∀ candidate,
      candidate ∈ bindings →
      candidate.abi = abi →
      candidate.name = name →
      candidate.parameterTypes = parameterTypes →
      candidate.returnType = returnType →
      candidate.behavior = selected.behavior

inductive CollectedExternFunctionScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.FunctionScheme) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.ExternFunction)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (parameterTypes : List Static.Ty)
      (returnType : Static.Ty)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.externFunction surface))
      (headerKind : header.kind = .externalFunction)
      (schemeMember : scheme ∈ context.functions)
      (declaration : scheme.declaration = header.declaration)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (parameters : ParameterTypesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.parameters parameterTypes)
      (schemeParameterTypes : scheme.parameterTypes = parameterTypes)
      (returned : ReturnTypeRetains
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.name surface.returnType returnType)
      (schemeReturnType : scheme.returnType = returnType)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements) :
      CollectedExternFunctionScheme pack catalog context header scheme

/-- An external function uses the same declaration-occurrence provenance as
    an internal callable scheme. -/
theorem CollectedExternFunctionScheme.source_declaration
    (collected : CollectedExternFunctionScheme pack catalog context header scheme) :
    ∃ address, header.source = .item address ∧
      scheme.declaration = header.declaration := by
  cases collected with
  | intro address _surface _genericParameters _parameterTypes _returnType
      _genericRequirements _whereRequirements source _headerMember
      _headerMatches _itemFound _headerKind _schemeMember declaration
      _namesUnique _parametersCollected _schemeParameters _parameters
      _schemeParameterTypes _returned _schemeReturnType _genericBounds
      _whereBounds _schemeRequirements =>
      exact ⟨address, source, declaration⟩

theorem CollectedExternFunctionScheme.signature_substitute_unique
    (collected : CollectedExternFunctionScheme pack catalog context header scheme)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      scheme.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      scheme.genericParameters typeArguments constArguments)
    (leftParameters : Static.substituteTypes leftSubstitution
      scheme.parameterTypes = some leftParameterTypes)
    (rightParameters : Static.substituteTypes rightSubstitution
      scheme.parameterTypes = some rightParameterTypes)
    (leftReturn : scheme.returnType.substitute leftSubstitution =
      some leftReturnType)
    (rightReturn : scheme.returnType.substitute rightSubstitution =
      some rightReturnType) :
    leftParameterTypes = rightParameterTypes ∧
      leftReturnType = rightReturnType := by
  cases collected with
  | intro address surface genericParameters retainedParameterTypes
      retainedReturnType genericRequirements whereRequirements source
      headerMember headerMatches itemFound headerKind schemeMember declaration
      namesUnique parametersCollected schemeParameters parameters
      schemeParameterTypes returned schemeReturnType genericBounds whereBounds
      schemeRequirements =>
      rw [schemeParameters] at leftBound rightBound
      rw [schemeParameterTypes] at leftParameters rightParameters
      rw [schemeReturnType] at leftReturn rightReturn
      have parameterEquality :=
        parameters.substitute_eq_of_arguments leftBound rightBound
      have returnEquality := returned.substitute_eq_of_arguments
        leftBound rightBound
      rw [leftParameters, rightParameters] at parameterEquality
      rw [leftReturn, rightReturn] at returnEquality
      exact ⟨Option.some.inj parameterEquality,
        Option.some.inj returnEquality⟩

inductive ExternFunctionLowers
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (bindings : List ExternalBinding)
    (surface : Surface.ExternFunction)
    (scheme : Static.FunctionScheme)
    (monomorphicInstance : Static.FunctionInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (groundParameters : List Static.GroundTy)
      (coreParameters : List (VarId × Core.Ty))
      (parameterContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (groundReturnType : Static.GroundTy)
      (coreReturnType : Core.Ty)
      (binding : ExternalBinding)
      (instantiated : Static.FunctionInstantiates baseContext.implementations
        scheme substitution monomorphicInstance)
      (declarationParameters : scheme.parameterTypes.length =
        surface.parameters.length)
      (parameters : ParametersLower { baseContext with substitution := substitution }
        none 0 surface.parameters groundParameters coreParameters parameterContext nextLocal)
      (parameterTypes : groundParameters = monomorphicInstance.parameterTypes)
      (returned : ReturnTypeGrounds { baseContext with substitution := substitution }
        surface.name surface.returnType groundReturnType)
      (selectedReturnType : groundReturnType = monomorphicInstance.returnType)
      (returnTypeCore : groundReturnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (selectedBinding : SelectsExternalBinding bindings surface.abi surface.name
        (coreParameters.map Prod.snd) coreReturnType binding)
      (definition : core = {
        id := monomorphicInstance.function
        parameters := coreParameters
        returnType := coreReturnType
        body := none
        external := some binding.behavior
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      ExternFunctionLowers program baseContext bindings surface scheme
        monomorphicInstance core

inductive CollectedExternFunctionLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (bindings : List ExternalBinding)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.FunctionScheme)
    (resolved : Static.FunctionInstance)
    (core : Core.Function) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.ExternFunction)
      (source : header.source = .item address)
      (itemFound : pack.item? address = some (.externFunction surface))
      (schemeCollected : CollectedExternFunctionScheme pack catalog context
        header scheme)
      (instanceMember : resolved ∈ context.functionInstances)
      (instanceDeclaration : resolved.declaration = header.declaration)
      (lowers : ExternFunctionLowers program (context.forModule header.moduleId)
        bindings surface scheme resolved core) :
      CollectedExternFunctionLowers pack catalog program context bindings header
        scheme resolved core

/-- Compile-time constant expressions are deliberately smaller than ordinary
    expressions. They contain literal values, references to constants already
    admitted by dependency order, and scalar casts/operators. In particular,
    a function call is not made into a constant expression merely because one
    execution happens not to mutate the world. -/
inductive ConstantExpression : Core.Expr → Prop where
  | value : ConstantExpression (.value value)
  | constant (constantId : ConstantId) :
      ConstantExpression (.constant constantId)
  | cast
      (operand : ConstantExpression expression) :
      ConstantExpression (.cast target expression)
  | unary
      (operand : ConstantExpression expression) :
      ConstantExpression (.unary operation expression)
  | binary
      (left : ConstantExpression leftExpression)
      (right : ConstantExpression rightExpression) :
      ConstantExpression (.binary operation leftExpression rightExpression)

/-- Constant initialization is evaluated before the constant is added to the
    available program. This gives dependencies an explicit order, rejects
    self/forward cycles, restricts initializers to the compile-time expression
    language above, and requires evaluation to leave heap and world state
    unchanged. -/
inductive ConstantLowers
    (availableProgram fullProgram : Core.Program)
    (context : SurfaceElaboration.Context)
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (header : Declarations.DeclarationHeader)
    (core : Core.Constant) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (name : Surface.Name)
      (isPublic : Bool)
      (surfaceType : Surface.TypeExpr)
      (surfaceValue : Surface.Expr)
      (entry : SurfaceElaboration.ConstantEntry)
      (groundType : Static.GroundTy)
      (coreType : Core.Ty)
      (coreExpression : Core.Expr)
      (value : Core.Value)
      (fuel : Nat)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address =
        some (.constant name isPublic surfaceType surfaceValue))
      (headerKind : header.kind = .constant)
      (entryMember : entry ∈ context.constants)
      (entryDeclaration : entry.declaration = header.declaration)
      (notYetAvailable : availableProgram.constant? entry.constant = none)
      (type : SurfaceElaboration.TypeGrounds (context.forModule header.moduleId)
        surfaceType groundType)
      (entryType : entry.type = groundType)
      (typeCore : groundType.toCore context.monomorphization = some coreType)
      (expression : SurfaceElaboration.ExprChecks (context.forModule header.moduleId)
        surfaceValue
        groundType coreExpression)
      (constantExpression : ConstantExpression coreExpression)
      (target : availableProgram.target = context.target)
      (evaluatesPurely : Semantics.evalExpr fuel availableProgram ({} : Semantics.State)
        coreExpression = .done value {})
      (definition : core = { id := entry.constant, type := coreType, value })
      (member : core ∈ fullProgram.constants)
      (typed : Typing.ConstantWellTyped fullProgram core) :
      ConstantLowers availableProgram fullProgram context pack catalog header core

def ConstantHeaderOrderCovers
    (catalog : Declarations.Catalog)
    (order : List Declarations.DeclarationHeader) : Prop :=
  order.Pairwise (fun left right => left ≠ right) ∧
    (∀ header, header ∈ order →
      header ∈ catalog.headers ∧ header.kind = .constant) ∧
    ∀ header, header ∈ catalog.headers → header.kind = .constant →
      header ∈ order

def programWithoutConstants (program : Core.Program) : Core.Program :=
  { program with constants := [] }

def programWithAppendedConstant
    (program : Core.Program) (constant : Core.Constant) : Core.Program :=
  { program with constants := program.constants ++ [constant] }

/-- A source pack may declare constants in any file order.  `order` is a
    dependency order over the collected constant headers; each initializer is
    evaluated against exactly the constants already admitted. -/
inductive ConstantsLowerInOrder
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (fullProgram : Core.Program) :
    Core.Program → List Declarations.DeclarationHeader → Prop where
  | nil
      (complete : available.constants = fullProgram.constants) :
      ConstantsLowerInOrder pack catalog context fullProgram available []
  | cons
      (core : Core.Constant)
      (lowered : ConstantLowers available fullProgram context pack catalog header core)
      (tail : ConstantsLowerInOrder pack catalog context fullProgram
        (programWithAppendedConstant available core) headers) :
      ConstantsLowerInOrder pack catalog context fullProgram available
        (header :: headers)

def ConstantsLower
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (program : Core.Program) : Prop :=
  ∃ order,
    ConstantHeaderOrderCovers catalog order ∧
      ConstantsLowerInOrder pack catalog context program
        (programWithoutConstants program) order

def CoreProgramIdsUnique (program : Core.Program) : Prop :=
  program.functions.Pairwise (fun left right => left.id ≠ right.id) ∧
    program.structures.Pairwise (fun left right => left.id ≠ right.id) ∧
    program.enumerations.Pairwise (fun left right => left.id ≠ right.id) ∧
    program.constants.Pairwise (fun left right => left.id ≠ right.id)

/-- Completeness is bidirectional: every collected source declaration receives
    semantic metadata, and every metadata row is justified by a collected
    source declaration.  This prevents a future compiler from satisfying the
    formal interface by silently omitting a declaration or inventing one. -/
structure DeclarationCollectionComplete
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context) : Prop where
  functions : ∀ header, header ∈ catalog.headers → header.kind = .function →
    ∃ scheme bodyContext,
      CollectedFunctionScheme pack catalog context header scheme bodyContext
  externalFunctions : ∀ header, header ∈ catalog.headers →
    header.kind = .externalFunction →
    ∃ scheme, CollectedExternFunctionScheme pack catalog context header scheme
  functionSchemes : ∀ scheme, scheme ∈ context.functions →
    ∃ header bodyContext, header ∈ catalog.headers ∧
      (CollectedFunctionScheme pack catalog context header scheme bodyContext ∨
       CollectedExternFunctionScheme pack catalog context header scheme)
  typeAliases : ∀ header, header ∈ catalog.headers →
    header.kind = .typeAlias →
    ∃ entry, CollectedTypeAlias pack catalog context header entry
  typeAliasEntries : ∀ entry, entry ∈ context.typeAliases →
    ∃ header, header ∈ catalog.headers ∧
      CollectedTypeAlias pack catalog context header entry
  nominals : ∀ header, header ∈ catalog.headers →
    (header.kind = .structureType ∨ header.kind = .enumeration) →
    ∃ scheme, CollectedNominalScheme pack catalog context header scheme
  nominalSchemes : ∀ scheme, scheme ∈ context.nominalSchemes →
    ∃ header, header ∈ catalog.headers ∧
      CollectedNominalScheme pack catalog context header scheme
  structConstructorHeaders : ∀ header, header ∈ catalog.headers →
    header.kind = .structureType →
    ∃ nominal constructor,
      CollectedStructConstructorScheme pack catalog context header nominal constructor
  structConstructorSchemes : ∀ constructor,
    constructor ∈ context.structConstructors →
    ∃ header nominal, header ∈ catalog.headers ∧
      CollectedStructConstructorScheme pack catalog context header nominal constructor
  variantConstructorHeaders : ∀ variantHeader,
    variantHeader ∈ catalog.headers → variantHeader.kind = .enumVariant →
    ∃ parentHeader nominal constructor,
      parentHeader ∈ catalog.headers ∧
      CollectedVariantConstructorScheme pack catalog context parentHeader
        variantHeader nominal constructor
  variantConstructorSchemes : ∀ constructor,
    constructor ∈ context.variantConstructors →
    ∃ parentHeader variantHeader nominal,
      parentHeader ∈ catalog.headers ∧ variantHeader ∈ catalog.headers ∧
      CollectedVariantConstructorScheme pack catalog context parentHeader
        variantHeader nominal constructor
  traits : ∀ header, header ∈ catalog.headers → header.kind = .trait →
    ∃ scheme, CollectedTraitScheme pack catalog context header scheme
  traitSchemes : ∀ scheme, scheme ∈ context.traits →
    ∃ header, header ∈ catalog.headers ∧
      CollectedTraitScheme pack catalog context header scheme
  traitMethodHeaders : ∀ methodHeader, methodHeader ∈ catalog.headers →
    methodHeader.kind = .traitMethod →
    ∃ parentHeader trait contract,
      parentHeader ∈ catalog.headers ∧
      CollectedTraitMethodContract pack catalog context parentHeader methodHeader
        trait contract
  traitMethodContracts : ∀ contract, contract ∈ context.traitMethods →
    ∃ parentHeader methodHeader trait,
      parentHeader ∈ catalog.headers ∧ methodHeader ∈ catalog.headers ∧
      CollectedTraitMethodContract pack catalog context parentHeader methodHeader
        trait contract
  implementations : ∀ header, header ∈ catalog.headers →
    header.kind = .implementation →
    ∃ scheme, CollectedImplScheme pack catalog context header scheme ∧
      match scheme.implementedTrait with
      | none => True
      | some _ => TraitImplementationConforms pack catalog context header scheme
  implementationSchemes : ∀ scheme, scheme ∈ context.implementations →
    ∃ header, header ∈ catalog.headers ∧
      CollectedImplScheme pack catalog context header scheme
  implementationMethodHeaders : ∀ methodHeader,
    methodHeader ∈ catalog.headers →
    methodHeader.kind = .implementationMethod →
    ∃ parentHeader implementation,
      parentHeader ∈ catalog.headers ∧
      CollectedImplScheme pack catalog context parentHeader implementation ∧
      ((implementation.implementedTrait = none ∧
        ∃ scheme bodyContext, CollectedInherentMethodScheme pack catalog context
          parentHeader methodHeader implementation scheme bodyContext) ∨
       (∃ pattern contract bodyContext parameterTypes returnType,
        implementation.implementedTrait = some pattern ∧
        CollectedTraitImplementationMethodConforms pack catalog context
          parentHeader methodHeader implementation contract bodyContext
          parameterTypes returnType))
  inherentMethodSchemes : ∀ scheme, scheme ∈ context.methods →
    ∃ parentHeader methodHeader implementation bodyContext,
      parentHeader ∈ catalog.headers ∧ methodHeader ∈ catalog.headers ∧
      CollectedInherentMethodScheme pack catalog context parentHeader methodHeader
        implementation scheme bodyContext

def RowsUniqueByKey
    (rows : List α) (key : α → κ) : Prop :=
  ∀ left, left ∈ rows → ∀ right, right ∈ rows →
    key left = key right → left = right

/-- Declaration-indexed semantic tables are functions, represented as compact
    rows. Bidirectional collection proves provenance; this invariant separately
    prevents one source declaration from acquiring conflicting metadata. -/
structure DeclarationMetadataUnique
    (context : SurfaceElaboration.Context) : Prop where
  functions : RowsUniqueByKey context.functions (fun row => row.declaration)
  methods : RowsUniqueByKey context.methods (fun row => row.declaration)
  traits : RowsUniqueByKey context.traits (fun row => row.declaration)
  traitMethods : RowsUniqueByKey context.traitMethods (fun row => row.declaration)
  implementations : RowsUniqueByKey context.implementations
    (fun row => row.declaration)
  implementationIds : RowsUniqueByKey context.implementations
    (fun row => row.id)
  constants : RowsUniqueByKey context.constants (fun row => row.declaration)
  typeAliases : RowsUniqueByKey context.typeAliases (fun row => row.declaration)
  nominalSchemes : RowsUniqueByKey context.nominalSchemes
    (fun row => row.declaration)
  structConstructors : RowsUniqueByKey context.structConstructors
    (fun row => row.declaration)
  structConstructorSourceTypes : RowsUniqueByKey context.structConstructors
    (fun row => row.sourceType)
  variantConstructors : RowsUniqueByKey context.variantConstructors
    (fun row => row.declaration)

/-- Retaining one source type into a declaration scheme is functional once the
    declaration tables are known to be functional.  The proof also makes the
    specified lookup priority explicit: builtins exclude every other path
    rule, and an in-scope type parameter excludes global nominal lookup. -/
theorem TypeRetains.unique
    (metadata : DeclarationMetadataUnique context)
    (left : TypeRetains context surface leftType)
    (right : TypeRetains context surface rightType) :
    leftType = rightType := by
  apply TypeRetains.rec
    (motive_1 := fun surface retained _ =>
      ∀ other, TypeRetains context surface other → retained = other)
    (motive_2 := fun surfaces retained _ =>
      ∀ other, TypesRetain context surfaces other → retained = other)
    (motive_3 := fun surface retained _ =>
      ∀ other, ArrayLengthRetains context surface other → retained = other)
    (motive_4 := fun surface retained _ =>
      ∀ other, ConstTypeArgumentRetains context surface other →
        retained = other)
    (motive_5 := fun parameters surfaces retainedTypes retainedConstants _ =>
      ∀ otherTypes otherConstants,
        NominalArgumentsRetain context parameters surfaces otherTypes
            otherConstants →
          retainedTypes = otherTypes ∧ retainedConstants = otherConstants)
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ left rightType right
  · intro segments name scalar leftSingle leftFound other rightCase
    cases rightCase with
    | builtin rightSingle rightFound =>
        have nameEquality := Option.some.inj (leftSingle.symm.trans rightSingle)
        cases nameEquality
        cases Option.some.inj (leftFound.symm.trans rightFound)
        rfl
    | parameter rightSingle rightNotBuiltin rightResolved =>
        have builtin := SurfaceElaboration.builtinTypePath_eq_of_single
          leftSingle leftFound
        simp [builtin] at rightNotBuiltin
    | nominal symbol rightNotBuiltin rightNotShadowed rightResolved rightMember
        rightDeclaration rightArgumentsFound rightArguments =>
        have builtin := SurfaceElaboration.builtinTypePath_eq_of_single
          leftSingle leftFound
        simp [builtin] at rightNotBuiltin
  · intro segments name binding leftSingle leftNotBuiltin leftResolved other
      rightCase
    cases rightCase with
    | builtin rightSingle rightFound =>
        have builtin := SurfaceElaboration.builtinTypePath_eq_of_single
          rightSingle rightFound
        simp [builtin] at leftNotBuiltin
    | parameter rightSingle rightNotBuiltin rightResolved =>
        have nameEquality := Option.some.inj (leftSingle.symm.trans rightSingle)
        cases nameEquality
        cases leftResolved.unique rightResolved
        rfl
    | nominal symbol rightNotBuiltin rightNotShadowed rightResolved rightMember
        rightDeclaration rightArgumentsFound rightArguments =>
        exact (rightNotShadowed name binding leftSingle leftResolved).elim
  · intro segments scheme surfaceArguments retainedTypes retainedConstants
      leftSymbol leftNotBuiltin leftNotShadowed leftResolved leftMember
      leftDeclaration leftArgumentsFound leftArguments argumentsInduction other
      rightCase
    cases rightCase with
    | builtin rightSingle rightFound =>
        have builtin := SurfaceElaboration.builtinTypePath_eq_of_single
          rightSingle rightFound
        simp [builtin] at leftNotBuiltin
    | parameter rightSingle rightNotBuiltin rightResolved =>
        exact (leftNotShadowed _ _ rightSingle rightResolved).elim
    | @nominal _ rightScheme rightSurfaceArguments rightRetainedTypes
        rightRetainedConstants rightSymbol rightNotBuiltin rightNotShadowed
        rightResolved rightMember rightDeclaration rightArgumentsFound
        rightArguments =>
        cases leftResolved with
        | intro leftReference leftFormed leftNameResolved =>
            cases rightResolved with
            | intro rightReference rightFormed rightNameResolved =>
                have referenceEquality : leftReference = rightReference :=
                  Option.some.inj (leftFormed.symm.trans rightFormed)
                subst rightReference
                have symbolDeclarationEquality :
                    rightSymbol.declaration = leftSymbol.declaration :=
                  leftNameResolved.2 rightSymbol rightNameResolved.1 |>.2
                have schemeDeclarationEquality :
                    scheme.declaration = rightScheme.declaration :=
                  leftDeclaration.trans
                    (symbolDeclarationEquality.symm.trans
                      rightDeclaration.symm)
                have schemeEquality := metadata.nominalSchemes scheme leftMember
                  rightScheme rightMember schemeDeclarationEquality
                subst rightScheme
                have surfaceArgumentsEquality := Option.some.inj
                  (leftArgumentsFound.symm.trans rightArgumentsFound)
                subst rightSurfaceArguments
                rcases argumentsInduction _ _ rightArguments with
                  ⟨rfl, rfl⟩
                rfl
  · intro surfaceElement retainedElement surfaceLength retainedLength
      leftElement leftLength elementInduction lengthInduction other rightCase
    cases rightCase with
    | array rightElement rightLength =>
        cases elementInduction _ rightElement
        cases lengthInduction _ rightLength
        rfl
  · intro surfaceElement retainedElement leftElement elementInduction other
      rightCase
    cases rightCase with
    | slice rightElement => cases elementInduction _ rightElement; rfl
  · intro surfaceReferent retainedReferent leftReferent referentInduction
      other rightCase
    cases rightCase with
    | reference rightReferent =>
        cases referentInduction _ rightReferent
        rfl
  · intro other rightCase
    cases rightCase
    rfl
  · intro surfaceHead retainedHead surfaceTail retainedTail leftHead leftTail
      headInduction tailInduction other rightCase
    cases rightCase with
    | cons rightHead rightTail =>
        cases headInduction _ rightHead
        cases tailInduction _ rightTail
        rfl
  · intro value other rightCase
    cases rightCase
    rfl
  · intro name binding leftResolved other rightCase
    cases rightCase with
    | parameter rightResolved =>
        cases leftResolved.unique rightResolved
        rfl
  · intro segments name binding leftSingle leftResolved other rightCase
    cases rightCase with
    | parameter rightSingle rightResolved =>
        have nameEquality := Option.some.inj (leftSingle.symm.trans rightSingle)
        cases nameEquality
        cases leftResolved.unique rightResolved
        rfl
  · intro otherTypes otherConstants rightCase
    cases rightCase
    exact ⟨rfl, rfl⟩
  · intro surfaceArgument retainedArgument parameters surfaceArguments
      retainedArguments retainedConstants parameter leftArgument leftTail
      argumentInduction tailInduction otherTypes otherConstants rightCase
    cases rightCase with
    | typeParameter rightArgument rightTail =>
        cases argumentInduction _ rightArgument
        rcases tailInduction _ _ rightTail with ⟨rfl, rfl⟩
        exact ⟨rfl, rfl⟩
  · intro surfaceArgument retainedArgument parameters surfaceArguments
      retainedArguments retainedConstants parameter leftArgument leftTail
      argumentInduction tailInduction otherTypes otherConstants rightCase
    cases rightCase with
    | constParameter rightArgument rightTail =>
        cases argumentInduction _ rightArgument
        rcases tailInduction _ _ rightTail with ⟨rfl, rfl⟩
        exact ⟨rfl, rfl⟩

theorem TypesRetain.unique
    (metadata : DeclarationMetadataUnique context)
    (left : TypesRetain context surfaces leftTypes)
    (right : TypesRetain context surfaces rightTypes) :
    leftTypes = rightTypes := by
  induction surfaces generalizing leftTypes rightTypes with
  | nil => cases left; cases right; rfl
  | cons surfaceHead surfaceTail induction =>
      cases left with
      | cons leftHead leftTail =>
          cases right with
          | cons rightHead rightTail =>
              cases leftHead.unique metadata rightHead
              cases induction leftTail rightTail
              rfl

theorem ConstTypeArgumentRetains.unique
    (left : ConstTypeArgumentRetains context surface leftConstant)
    (right : ConstTypeArgumentRetains context surface rightConstant) :
    leftConstant = rightConstant := by
  cases left with
  | parameter leftSingle leftResolved =>
      cases right with
      | parameter rightSingle rightResolved =>
          have nameEquality := Option.some.inj (leftSingle.symm.trans rightSingle)
          cases nameEquality
          cases leftResolved.unique rightResolved
          rfl

/-- Explicit generic syntax fixes the ordered symbolic argument vector even
    when the two derivations use extensionally different substitution maps.
    Each source type/const argument is retained functionally, and both maps
    must bind that retained value at the declaration's parameter ID. -/
theorem GenericArgumentsRetain.orderedArguments_unique
    (metadata : DeclarationMetadataUnique context)
    (left : GenericArgumentsRetain context leftSubstitution parameters
      surfaceArguments)
    (right : GenericArgumentsRetain context rightSubstitution parameters
      surfaceArguments)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution parameters
      leftTypeArguments leftConstArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution parameters
      rightTypeArguments rightConstArguments) :
    leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments := by
  induction left generalizing rightSubstitution leftTypeArguments
      leftConstArguments rightTypeArguments rightConstArguments with
  | nil =>
      cases right
      cases leftBound
      cases rightBound
      exact ⟨rfl, rfl⟩
  | @typeParameter surfaceArgument retainedArgument tailParameters
      tailSurface parameter leftArgument leftFound leftTail induction =>
      cases right with
      | typeParameter rightArgument rightFound rightTail =>
          cases leftBound with
          | typeParameter leftBoundFound leftBoundTail =>
              cases rightBound with
              | typeParameter rightBoundFound rightBoundTail =>
                  cases TypeRetains.unique metadata leftArgument rightArgument
                  have leftHeadEquality := Option.some.inj
                    (leftFound.symm.trans leftBoundFound)
                  have rightHeadEquality := Option.some.inj
                    (rightFound.symm.trans rightBoundFound)
                  cases leftHeadEquality
                  cases rightHeadEquality
                  rcases induction rightTail leftBoundTail rightBoundTail with
                    ⟨rfl, rfl⟩
                  exact ⟨rfl, rfl⟩
  | @constParameter surfaceArgument retainedArgument tailParameters
      tailSurface parameter leftArgument leftFound leftTail induction =>
      cases right with
      | constParameter rightArgument rightFound rightTail =>
          cases leftBound with
          | constParameter leftBoundFound leftBoundTail =>
              cases rightBound with
              | constParameter rightBoundFound rightBoundTail =>
                  cases leftArgument.unique rightArgument
                  have leftHeadEquality := Option.some.inj
                    (leftFound.symm.trans leftBoundFound)
                  have rightHeadEquality := Option.some.inj
                    (rightFound.symm.trans rightBoundFound)
                  cases leftHeadEquality
                  cases rightHeadEquality
                  rcases induction rightTail leftBoundTail rightBoundTail with
                    ⟨rfl, rfl⟩
                  exact ⟨rfl, rfl⟩

theorem ExplicitGenericArgumentsRetain.orderedArguments_unique
    (metadata : DeclarationMetadataUnique context)
    (left : ExplicitGenericArgumentsRetain context path parameters
      leftSubstitution)
    (right : ExplicitGenericArgumentsRetain context path parameters
      rightSubstitution)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution parameters
      leftTypeArguments leftConstArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution parameters
      rightTypeArguments rightConstArguments) :
    leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments := by
  obtain ⟨leftHead, leftTail, leftFound, leftArguments⟩ := left
  obtain ⟨rightHead, rightTail, rightFound, rightArguments⟩ := right
  have surfaceArgumentsEquality := Option.some.inj
    (leftFound.symm.trans rightFound)
  cases surfaceArgumentsEquality
  exact leftArguments.orderedArguments_unique metadata rightArguments
    leftBound rightBound

/-- In a complete declaration table, concrete constant resolution denotes one
    metadata row. `ResolvesConstant` establishes the declaration identity;
    declaration-key uniqueness upgrades that identity to record equality. -/
theorem resolvesConstant_unique
    (metadata : DeclarationMetadataUnique context)
    (leftResolved : SurfaceElaboration.ResolvesConstant context path left)
    (rightResolved : SurfaceElaboration.ResolvesConstant context path right) :
    left = right := by
  cases leftResolved with
  | intro _leftNotShadowed leftSymbol leftNameResolved leftMember leftDeclaration =>
      cases rightResolved with
      | intro _rightNotShadowed rightSymbol rightNameResolved rightMember
          rightDeclaration =>
          cases leftNameResolved with
          | intro leftReference leftFormed leftResolved =>
              cases rightNameResolved with
              | intro rightReference rightFormed rightResolved =>
                  have referenceEquality : leftReference = rightReference :=
                    Option.some.inj (leftFormed.symm.trans rightFormed)
                  subst rightReference
                  have symbolDeclarationEquality :
                      rightSymbol.declaration = leftSymbol.declaration :=
                    leftResolved.2 rightSymbol rightResolved.1 |>.2
                  have rowDeclarationEquality :
                      left.declaration = right.declaration :=
                    leftDeclaration.trans
                      (symbolDeclarationEquality.symm.trans rightDeclaration.symm)
                  exact metadata.constants left leftMember right rightMember
                    rowDeclarationEquality

/-- In a complete declaration table, resolving one source struct path selects
    one complete constructor scheme. Name resolution fixes the declaration and
    declaration-key uniqueness fixes every retained field of the scheme. -/
theorem selectsStructConstructor_unique
    (metadata : DeclarationMetadataUnique context)
    (leftSelected : SurfaceElaboration.SelectsStructConstructor
      context path left)
    (rightSelected : SurfaceElaboration.SelectsStructConstructor
      context path right) :
    left = right := by
  rcases leftSelected with
    ⟨leftSymbol, leftResolved, leftMember, leftDeclaration, _leftUnique⟩
  rcases rightSelected with
    ⟨rightSymbol, rightResolved, rightMember, rightDeclaration, _rightUnique⟩
  cases leftResolved with
  | intro leftReference leftFormed leftNameResolved =>
      cases rightResolved with
      | intro rightReference rightFormed rightNameResolved =>
          have referenceEquality : leftReference = rightReference :=
            Option.some.inj (leftFormed.symm.trans rightFormed)
          subst rightReference
          have symbolDeclarationEquality :
              rightSymbol.declaration = leftSymbol.declaration :=
            leftNameResolved.2 rightSymbol rightNameResolved.1 |>.2
          have constructorDeclarationEquality :
              left.declaration = right.declaration :=
            leftDeclaration.trans
              (symbolDeclarationEquality.symm.trans rightDeclaration.symm)
          exact metadata.structConstructors left leftMember right rightMember
            constructorDeclarationEquality

/-- In a complete declaration table, resolving one source variant path selects
    one complete constructor record. Name resolution already forces all
    candidates to denote one declaration; declaration-key uniqueness upgrades
    that identity agreement to record equality. -/
theorem selectsVariantConstructor_unique
    (metadata : DeclarationMetadataUnique context)
    (leftSelected : SurfaceElaboration.SelectsVariantConstructor
      context path left)
    (rightSelected : SurfaceElaboration.SelectsVariantConstructor
      context path right) :
    left = right := by
  rcases leftSelected with
    ⟨_leftNotShadowed, leftSymbol, leftResolved, leftMember,
      leftDeclaration, _leftUnique⟩
  rcases rightSelected with
    ⟨_rightNotShadowed, rightSymbol, rightResolved, rightMember,
      rightDeclaration, _rightUnique⟩
  cases leftResolved with
  | intro leftReference leftFormed leftNameResolved =>
      cases rightResolved with
      | intro rightReference rightFormed rightNameResolved =>
          have referenceEquality : leftReference = rightReference :=
            Option.some.inj (leftFormed.symm.trans rightFormed)
          subst rightReference
          have symbolDeclarationEquality :
              rightSymbol.declaration = leftSymbol.declaration :=
            leftNameResolved.2 rightSymbol rightNameResolved.1 |>.2
          have constructorDeclarationEquality :
              left.declaration = right.declaration :=
            leftDeclaration.trans
              (symbolDeclarationEquality.symm.trans rightDeclaration.symm)
          exact metadata.variantConstructors left leftMember right rightMember
            constructorDeclarationEquality

/-- The symbolic wrapper adds lexical shadowing, but constructor identity is
    still inherited from the complete declaration table. -/
theorem selectsSymbolicVariantConstructor_unique
    (metadata : DeclarationMetadataUnique symbolic.globals)
    (leftSelected : SelectsSymbolicVariantConstructor symbolic path left)
    (rightSelected : SelectsSymbolicVariantConstructor symbolic path right) :
    left = right :=
  selectsVariantConstructor_unique metadata leftSelected.2 rightSelected.2

/-- Complete declaration metadata turns `SelectsImpl`'s identity-level
    ambiguity check into uniqueness of the selected implementation record. -/
theorem selectsImpl_unique
    (metadata : DeclarationMetadataUnique context)
    (leftSelected : Static.SelectsImpl context.implementations goal left)
    (rightSelected : Static.SelectsImpl context.implementations goal right) :
    left = right := by
  rcases leftSelected with ⟨leftApplies, leftUnique⟩
  rcases rightSelected with ⟨rightApplies, _rightUnique⟩
  have sameId : right.id = left.id := leftUnique right rightApplies
  cases leftApplies with
  | intro leftMember leftSubstitution leftBound leftPattern leftImplements
      leftHeader leftRequirements =>
      cases rightApplies with
      | intro rightMember rightSubstitution rightBound rightPattern rightImplements
          rightHeader rightRequirements =>
          exact metadata.implementationIds left leftMember right rightMember sameId.symm

/-- Every emitted specialization of a source function is tied to the exact
    source body that was checked once at the declaration's symbolic generic
    types. This is the provenance bridge between declaration-wide generic-body
    checking and per-specialization concrete lowering; the two witnesses cannot
    silently describe different source functions or different scheme rows. -/
theorem CollectedFunctionLowers.hasSymbolicallyTypedSource
    (lowered : CollectedFunctionLowers pack catalog program baseContext header
      scheme monomorphicInstance core) :
    ∃ address surface genericParameters substitution,
      header.source = .item address ∧
      pack.item? address = some (.function surface) ∧
      SourceWellFormed.FunctionBodyWellScoped
        (baseContext.forModule header.moduleId) surface.parameters surface.body ∧
      FunctionBodySymbolicallyTyped
        (withGenericParameters (baseContext.forModule header.moduleId)
          genericParameters)
        scheme.requirements surface.parameters scheme.parameterTypes
        scheme.returnType surface.body ∧
      Static.instantiateTypes substitution scheme.parameterTypes =
        some monomorphicInstance.parameterTypes ∧
      scheme.returnType.instantiate substitution =
        some monomorphicInstance.returnType ∧
      FunctionLowers program
        (withGenericParameters (baseContext.forModule header.moduleId)
          genericParameters)
        surface scheme monomorphicInstance core := by
  cases lowered with
  | intro address surface bodyContext source itemFound schemeCollected
      instanceMember instanceDeclaration specializes =>
      cases schemeCollected with
      | intro collectedAddress collectedSurface genericParameters parameterTypes
          returnType genericRequirements whereRequirements collectedSource
          collectedHeaderMember collectedHeaderMatches collectedItemFound
          collectedHeaderKind collectedSchemeMember collectedDeclaration
          namesUnique parametersCollected schemeParameters parameters
          schemeParameterTypes returned schemeReturnType genericBounds whereBounds
          schemeRequirements bodyScoped bodyTyped =>
          have addressEquality : address = collectedAddress := by
            have sameSource : Declarations.DeclarationOccurrence.item address =
                .item collectedAddress := source.symm.trans collectedSource
            injection sameSource
          subst collectedAddress
          have surfaceEquality : surface = collectedSurface := by
            rw [itemFound] at collectedItemFound
            injection collectedItemFound with itemEquality
            injection itemEquality
          subst collectedSurface
          obtain ⟨substitution, parameterTypesInstantiate,
            returnTypeInstantiates⟩ := specializes.instanceTypes
          exact ⟨address, surface, genericParameters, substitution, source,
            itemFound, bodyScoped, specializes.symbolic,
            parameterTypesInstantiate, returnTypeInstantiates,
            specializes.lowers⟩

structure MonomorphicArtifactsComplete
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (externalBindings : List ExternalBinding) : Prop where
  nominalInstancesUnique : Static.NominalInstancesUnique context.nominalInstances
  functionInstanceIdsUnique : RowsUniqueByKey context.functionInstances
    (fun row => row.function)
  functionSpecializationsUnique : RowsUniqueByKey context.functionInstances
    Static.FunctionInstance.specializationKey
  methodInstanceIdsUnique : RowsUniqueByKey context.methodInstances
    (fun row => row.function)
  methodSpecializationsUnique : RowsUniqueByKey context.methodInstances
    Static.MethodInstance.specializationKey
  methodLookupCoherent : Static.MethodLookupCoherent
    context.implementations context.methods context.methodInstances
  traitImplementationMethodInstanceIdsUnique :
    RowsUniqueByKey context.traitImplementationMethodInstances
      (fun row => row.function)
  nominalInstancesMapped : ∀ resolved, resolved ∈ context.nominalInstances →
    Static.NominalInstanceMapped context.monomorphization resolved
  nominalInstancesLower : ∀ resolved, resolved ∈ context.nominalInstances →
    ∃ header scheme,
      header ∈ catalog.headers ∧ scheme ∈ context.nominalSchemes ∧
      (∃ core, CollectedMonomorphicStructLowers pack catalog program context
        header scheme resolved core) ∨
      (∃ core, CollectedMonomorphicEnumLowers pack catalog program context
        header scheme resolved core)
  functionInstancesLower : ∀ resolved, resolved ∈ context.functionInstances →
    ∃ header scheme core,
      header ∈ catalog.headers ∧ scheme ∈ context.functions ∧
      (CollectedFunctionLowers pack catalog program context header scheme resolved core ∨
       CollectedExternFunctionLowers pack catalog program context externalBindings
         header scheme resolved core)
  inherentMethodInstancesLower : ∀ resolved, resolved ∈ context.methodInstances →
    ∃ parentHeader methodHeader implementation scheme core,
      parentHeader ∈ catalog.headers ∧ methodHeader ∈ catalog.headers ∧
      scheme ∈ context.methods ∧
      CollectedInherentMethodFunctionLowers pack catalog program context
        parentHeader methodHeader implementation scheme resolved core
  traitImplementationMethodInstancesLower : ∀ resolved,
    resolved ∈ context.traitImplementationMethodInstances →
    ∃ parentHeader methodHeader implementation contract core,
      parentHeader ∈ catalog.headers ∧ methodHeader ∈ catalog.headers ∧
      TraitImplementationMethodFunctionLowers pack catalog program context
        parentHeader methodHeader implementation contract resolved core
  structuresCovered : ∀ core, core ∈ program.structures →
    ∃ header scheme resolved,
      CollectedMonomorphicStructLowers pack catalog program context
        header scheme resolved core
  enumerationsCovered : ∀ core, core ∈ program.enumerations →
    ∃ header scheme resolved,
      CollectedMonomorphicEnumLowers pack catalog program context
        header scheme resolved core
  functionsCovered : ∀ core, core ∈ program.functions →
    (∃ header scheme resolved,
      CollectedFunctionLowers pack catalog program context header scheme resolved core) ∨
    (∃ header scheme resolved,
      CollectedExternFunctionLowers pack catalog program context externalBindings
        header scheme resolved core) ∨
    (∃ parentHeader methodHeader implementation scheme resolved,
      CollectedInherentMethodFunctionLowers pack catalog program context
        parentHeader methodHeader implementation scheme resolved core) ∨
    (∃ parentHeader methodHeader implementation contract resolved,
      TraitImplementationMethodFunctionLowers pack catalog program context
        parentHeader methodHeader implementation contract resolved core)
  constantsLower : ConstantsLower pack catalog context program

/-- One nominal source type and ordered generic argument vector identify one
    emitted nominal artifact in a complete table. -/
theorem MonomorphicArtifactsComplete.nominalArtifact_unique
    (artifacts : MonomorphicArtifactsComplete pack catalog program context
      bindings)
    (leftDemand : NominalArtifactDemand context declaration sourceType kind
      typeArguments constArguments left)
    (rightDemand : NominalArtifactDemand context declaration sourceType kind
      typeArguments constArguments right) :
    left = right := by
  cases leftDemand with
  | intro leftMember _leftDeclaration leftSourceType _leftKind
      leftTypeArguments leftConstArguments _leftUnique =>
      cases rightDemand with
      | intro rightMember _rightDeclaration rightSourceType _rightKind
          rightTypeArguments rightConstArguments _rightUnique =>
          exact artifacts.nominalInstancesUnique left leftMember right rightMember
            (leftSourceType.trans rightSourceType.symm)
            (leftTypeArguments.trans rightTypeArguments.symm)
            (leftConstArguments.trans rightConstArguments.symm)

/-- One selected function declaration and ordered generic argument vector
    identify one emitted function artifact in a complete table. -/
theorem MonomorphicArtifactsComplete.functionArtifact_unique
    (artifacts : MonomorphicArtifactsComplete pack catalog program context
      bindings)
    (leftDemand : FunctionArtifactDemand context path scheme typeArguments
      constArguments left)
    (rightDemand : FunctionArtifactDemand context path scheme typeArguments
      constArguments right) :
    left = right := by
  cases leftDemand with
  | intro leftMember leftDeclaration leftTypeArguments leftConstArguments
      _leftUnique =>
      cases rightDemand with
      | intro rightMember rightDeclaration rightTypeArguments rightConstArguments
          _rightUnique =>
          apply artifacts.functionSpecializationsUnique left leftMember right
            rightMember
          simp [Static.FunctionInstance.specializationKey, leftDeclaration,
            rightDeclaration, leftTypeArguments, rightTypeArguments,
            leftConstArguments, rightConstArguments]

/-- For methods, the ground receiver joins the declaration and generic
    arguments in the artifact identity. -/
theorem MonomorphicArtifactsComplete.methodArtifact_unique
    (artifacts : MonomorphicArtifactsComplete pack catalog program context
      bindings)
    (receiverEquality : left.receiverType = right.receiverType)
    (leftDemand : MethodArtifactDemand context scheme typeArguments
      constArguments left)
    (rightDemand : MethodArtifactDemand context scheme typeArguments
      constArguments right) :
    left = right := by
  cases leftDemand with
  | intro leftMember leftDeclaration _leftName _leftReceiverMode
      leftTypeArguments leftConstArguments _leftUnique =>
      cases rightDemand with
      | intro rightMember rightDeclaration _rightName _rightReceiverMode
          rightTypeArguments rightConstArguments _rightUnique =>
          apply artifacts.methodSpecializationsUnique left leftMember right
            rightMember
          simp [Static.MethodInstance.specializationKey, leftDeclaration,
            rightDeclaration, receiverEquality, leftTypeArguments,
            rightTypeArguments, leftConstArguments, rightConstArguments]

/-- A complete artifact table cannot make one resolved call target denote two
    different function-instance records. Resolution already rejects distinct
    applicable core IDs; artifact-ID uniqueness upgrades that agreement to
    equality of the complete selected records. -/
theorem resolvesFunction_unique
    (artifacts : MonomorphicArtifactsComplete pack catalog program context bindings)
    (leftResolved : Static.ResolvesFunction context.implementations
      context.functions context.functionInstances argumentTypes leftScheme left)
    (rightResolved : Static.ResolvesFunction context.implementations
      context.functions context.functionInstances argumentTypes rightScheme right) :
    left = right := by
  rcases leftResolved with ⟨_leftSchemeMember,
    ⟨leftMember, _leftApplies⟩, leftUnique⟩
  rcases rightResolved with ⟨rightSchemeMember, rightApplies, _rightUnique⟩
  rcases rightApplies with ⟨rightMember, rightApplies⟩
  have sameFunction : right.function = left.function :=
    leftUnique rightScheme right rightSchemeMember ⟨rightMember, rightApplies⟩
  exact artifacts.functionInstanceIdsUnique
    left leftMember right rightMember sameFunction.symm

/-- Method resolution has the same identity discipline as direct calls: a
    resolved core function ID names exactly one complete method instance. -/
theorem resolvesMethod_unique
    (artifacts : MonomorphicArtifactsComplete pack catalog program context bindings)
    (leftResolved : Static.ResolvesMethod context.implementations context.methods
      context.methodInstances context.currentModule receiver name argumentTypes
      leftScheme left)
    (rightResolved : Static.ResolvesMethod context.implementations context.methods
      context.methodInstances context.currentModule receiver name argumentTypes
      rightScheme right) :
    left = right := by
  rcases leftResolved with ⟨_leftSchemeMember,
    leftApplies, _leftPreferred, leftUnique⟩
  rcases rightResolved with
    ⟨rightSchemeMember, rightApplies, rightPreferred, _rightUnique⟩
  have leftMember := leftApplies.1.1
  have rightMember := rightApplies.1.1
  have sameFunction : right.function = left.function :=
    leftUnique rightScheme right rightSchemeMember rightApplies
      rightPreferred
  exact artifacts.methodInstanceIdsUnique
    left leftMember right rightMember sameFunction.symm

structure CompleteProgramElaboration
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (externalBindings : List ExternalBinding) : Prop where
  sourcePack : Declarations.SourcePackWellFormed pack
  declarationCatalog : Declarations.CatalogWellFormed pack catalog
  importCollection : Declarations.ImportCollectionCovers pack imports
  importOrder : ∃ order, Declarations.ModuleDependencyOrderCovers pack imports order
  names : context.names = Declarations.nameEnvironment pack catalog imports
  target : program.target = context.target
  declarations : DeclarationCollectionComplete pack catalog context
  metadataUnique : DeclarationMetadataUnique context
  implementationsCoherent : Static.ImplementationsCoherent context.implementations
  artifacts : MonomorphicArtifactsComplete pack catalog program context externalBindings
  coreIds : CoreProgramIdsUnique program
  typed : Typing.ProgramWellTyped program
  layouts : Layout.ProgramHasLayouts program

/-- Every callable scheme, internal or external, inherits signature
    substitution functionality from its collected source declaration. -/
theorem CompleteProgramElaboration.functionSignatureSubstitute_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (schemeMember : scheme ∈ context.functions)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      scheme.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      scheme.genericParameters typeArguments constArguments)
    (leftParameters : Static.substituteTypes leftSubstitution
      scheme.parameterTypes = some leftParameterTypes)
    (rightParameters : Static.substituteTypes rightSubstitution
      scheme.parameterTypes = some rightParameterTypes)
    (leftReturn : scheme.returnType.substitute leftSubstitution =
      some leftReturnType)
    (rightReturn : scheme.returnType.substitute rightSubstitution =
      some rightReturnType) :
    leftParameterTypes = rightParameterTypes ∧
      leftReturnType = rightReturnType := by
  obtain ⟨header, bodyContext, _headerMember, collected | collected⟩ :=
    complete.declarations.functionSchemes scheme schemeMember
  · exact collected.signature_substitute_unique leftBound rightBound
      leftParameters rightParameters leftReturn rightReturn
  · exact collected.signature_substitute_unique leftBound rightBound
      leftParameters rightParameters leftReturn rightReturn

/-- Every source-selectable method scheme comes from an inherent method
    declaration, whose receiver, argument, and return types are functional in
    the ordered generic argument vector. -/
theorem CompleteProgramElaboration.methodSignatureSubstitute_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (schemeMember : scheme ∈ context.methods)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      scheme.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      scheme.genericParameters typeArguments constArguments)
    (leftReceiver : scheme.receiverType.substitute leftSubstitution =
      some leftReceiverType)
    (rightReceiver : scheme.receiverType.substitute rightSubstitution =
      some rightReceiverType)
    (leftArguments : Static.substituteTypes leftSubstitution
      scheme.argumentTypes = some leftArgumentTypes)
    (rightArguments : Static.substituteTypes rightSubstitution
      scheme.argumentTypes = some rightArgumentTypes)
    (leftReturn : scheme.returnType.substitute leftSubstitution =
      some leftReturnType)
    (rightReturn : scheme.returnType.substitute rightSubstitution =
      some rightReturnType) :
    leftReceiverType = rightReceiverType ∧
      leftArgumentTypes = rightArgumentTypes ∧
      leftReturnType = rightReturnType := by
  obtain ⟨parentHeader, methodHeader, implementation, bodyContext,
    _parentMember, _methodMember, collected⟩ :=
    complete.declarations.inherentMethodSchemes scheme schemeMember
  exact collected.signature_substitute_unique leftBound rightBound
    leftReceiver rightReceiver leftArguments rightArguments leftReturn
    rightReturn

/-- Complete-program declaration provenance exposes the retained payload proof
    needed to make a selected variant's symbolic payload substitution
    functional. -/
theorem CompleteProgramElaboration.variantPayloadSubstitute_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (member : constructor ∈ context.variantConstructors)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      constructor.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      constructor.genericParameters typeArguments constArguments)
    (leftSubstituted : Static.substituteTypes leftSubstitution
      constructor.payload = some leftPayload)
    (rightSubstituted : Static.substituteTypes rightSubstitution
      constructor.payload = some rightPayload) :
    leftPayload = rightPayload := by
  obtain ⟨parentHeader, variantHeader, nominal, _parentMember, _variantMember,
    collected⟩ := complete.declarations.variantConstructorSchemes constructor member
  exact collected.payload_substitute_unique leftBound rightBound
    leftSubstituted rightSubstituted

/-- The same provenance principle for one field of a selected struct
    constructor. -/
theorem CompleteProgramElaboration.structFieldSubstitute_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (constructorMember : constructor ∈ context.structConstructors)
    (fieldMember : field ∈ constructor.fields)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      constructor.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      constructor.genericParameters typeArguments constArguments)
    (leftSubstituted : field.type.substitute leftSubstitution = some leftType)
    (rightSubstituted : field.type.substitute rightSubstitution = some rightType) :
    leftType = rightType := by
  obtain ⟨header, nominal, _headerMember, collected⟩ :=
    complete.declarations.structConstructorSchemes constructor constructorMember
  exact collected.field_substitute_unique fieldMember leftBound rightBound
    leftSubstituted rightSubstituted

/-- Equal symbolic nominal arguments select the same complete monomorphic
    artifact, even when their witnessing substitutions differ away from the
    declaration's generic parameter domain. -/
theorem CompleteProgramElaboration.nominalEvidenceArtifact_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (left : NominalInstantiationEvidence outer concrete symbolic parameters
      requirements declaration sourceType kind leftInner leftTypeArguments
      leftConstArguments leftResolved)
    (right : NominalInstantiationEvidence outer concrete symbolic parameters
      requirements declaration sourceType kind rightInner rightTypeArguments
      rightConstArguments rightResolved)
    (typeArgumentsEquality : leftTypeArguments = rightTypeArguments)
    (constArgumentsEquality : leftConstArguments = rightConstArguments) :
    leftResolved = rightResolved := by
  have instantiatedTypesEquality := congrArg
    (Static.instantiateTypes outer) typeArgumentsEquality
  have instantiatedConstantsEquality := congrArg
    (Static.instantiateConstants outer) constArgumentsEquality
  have groundTypesEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      (instantiatedTypesEquality.trans right.typeArgumentsGround))
  have groundConstantsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      (instantiatedConstantsEquality.trans right.constArgumentsGround))
  cases left.artifact with
  | intro leftMember _leftDeclaration leftSourceType _leftKind
      leftTypeArguments leftConstArguments _leftUnique =>
      cases right.artifact with
      | intro rightMember _rightDeclaration rightSourceType _rightKind
          rightTypeArguments rightConstArguments _rightUnique =>
          have leftMemberGlobal :
              leftResolved ∈ symbolic.globals.nominalInstances := by
            rw [contexts.globals] at leftMember
            exact leftMember
          have rightMemberGlobal :
              rightResolved ∈ symbolic.globals.nominalInstances := by
            rw [contexts.globals] at rightMember
            exact rightMember
          exact complete.artifacts.nominalInstancesUnique
            leftResolved leftMemberGlobal rightResolved rightMemberGlobal
            (leftSourceType.trans rightSourceType.symm)
            (leftTypeArguments.trans
              (groundTypesEquality.trans rightTypeArguments.symm))
            (leftConstArguments.trans
              (groundConstantsEquality.trans rightConstArguments.symm))

/-- Contextual checking carries the finite artifact demand directly rather
    than through `NominalInstantiationEvidence`. The same complete-table key
    still makes the selected concrete row functional. -/
theorem CompleteProgramElaboration.concreteNominalArtifact_unique
    {symbolic : SymbolicBodyContext}
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (left : NominalArtifactDemand concrete declaration sourceType kind
      leftGroundTypeArguments leftGroundConstArguments leftResolved)
    (right : NominalArtifactDemand concrete declaration sourceType kind
      rightGroundTypeArguments rightGroundConstArguments rightResolved)
    (typeArgumentsEquality : leftGroundTypeArguments = rightGroundTypeArguments)
    (constArgumentsEquality :
      leftGroundConstArguments = rightGroundConstArguments) :
    leftResolved = rightResolved := by
  cases left with
  | intro leftMember _leftDeclaration leftSourceType _leftKind
      leftTypeArguments leftConstArguments _leftUnique =>
      cases right with
      | intro rightMember _rightDeclaration rightSourceType _rightKind
          rightTypeArguments rightConstArguments _rightUnique =>
          have leftMemberGlobal :
              leftResolved ∈ symbolic.globals.nominalInstances := by
            rw [contexts.globals] at leftMember
            exact leftMember
          have rightMemberGlobal :
              rightResolved ∈ symbolic.globals.nominalInstances := by
            rw [contexts.globals] at rightMember
            exact rightMember
          exact complete.artifacts.nominalInstancesUnique
            leftResolved leftMemberGlobal rightResolved rightMemberGlobal
            (leftSourceType.trans rightSourceType.symm)
            (leftTypeArguments.trans
              (typeArgumentsEquality.trans rightTypeArguments.symm))
            (leftConstArguments.trans
              (constArgumentsEquality.trans rightConstArguments.symm))

/-- Equal ground generic arguments identify one emitted function artifact in
    the complete table. This is the direct-call analogue of contextual nominal
    artifact identity; source selection has already fixed `scheme`. -/
theorem CompleteProgramElaboration.concreteFunctionArtifact_unique
    {symbolic : SymbolicBodyContext}
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (left : FunctionArtifactDemand concrete path scheme
      leftGroundTypeArguments leftGroundConstArguments leftResolved)
    (right : FunctionArtifactDemand concrete path scheme
      rightGroundTypeArguments rightGroundConstArguments rightResolved)
    (typeArgumentsEquality :
      leftGroundTypeArguments = rightGroundTypeArguments)
    (constArgumentsEquality :
      leftGroundConstArguments = rightGroundConstArguments) :
    leftResolved = rightResolved := by
  cases left with
  | intro leftMember leftDeclaration leftTypeArguments leftConstArguments
      _leftUnique =>
      cases right with
      | intro rightMember rightDeclaration rightTypeArguments
          rightConstArguments _rightUnique =>
          have leftMemberGlobal :
              leftResolved ∈ symbolic.globals.functionInstances := by
            rw [contexts.globals] at leftMember
            exact leftMember
          have rightMemberGlobal :
              rightResolved ∈ symbolic.globals.functionInstances := by
            rw [contexts.globals] at rightMember
            exact rightMember
          apply complete.artifacts.functionSpecializationsUnique
            leftResolved leftMemberGlobal rightResolved rightMemberGlobal
          simp [Static.FunctionInstance.specializationKey, leftDeclaration,
            rightDeclaration, leftTypeArguments, rightTypeArguments,
            leftConstArguments, rightConstArguments, typeArgumentsEquality,
            constArgumentsEquality]

/-- A method specialization key additionally includes its ground receiver.
    Once symbolic signature functionality aligns that receiver and the ordered
    generic arguments, the complete table identifies one emitted method row. -/
theorem CompleteProgramElaboration.concreteMethodArtifact_unique
    {symbolic : SymbolicBodyContext}
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (receiverEquality : leftResolved.receiverType = rightResolved.receiverType)
    (left : MethodArtifactDemand concrete scheme leftGroundTypeArguments
      leftGroundConstArguments leftResolved)
    (right : MethodArtifactDemand concrete scheme rightGroundTypeArguments
      rightGroundConstArguments rightResolved)
    (typeArgumentsEquality :
      leftGroundTypeArguments = rightGroundTypeArguments)
    (constArgumentsEquality :
      leftGroundConstArguments = rightGroundConstArguments) :
    leftResolved = rightResolved := by
  cases left with
  | intro leftMember leftDeclaration _leftName _leftReceiverMode
      leftTypeArguments leftConstArguments _leftUnique =>
      cases right with
      | intro rightMember rightDeclaration _rightName _rightReceiverMode
          rightTypeArguments rightConstArguments _rightUnique =>
          have leftMemberGlobal :
              leftResolved ∈ symbolic.globals.methodInstances := by
            rw [contexts.globals] at leftMember
            exact leftMember
          have rightMemberGlobal :
              rightResolved ∈ symbolic.globals.methodInstances := by
            rw [contexts.globals] at rightMember
            exact rightMember
          apply complete.artifacts.methodSpecializationsUnique
            leftResolved leftMemberGlobal rightResolved rightMemberGlobal
          simp [Static.MethodInstance.specializationKey, leftDeclaration,
            rightDeclaration, receiverEquality, leftTypeArguments,
            rightTypeArguments, leftConstArguments, rightConstArguments,
            typeArgumentsEquality, constArgumentsEquality]

/-- Within a complete program, a symbolic variant path selects one complete
    constructor record, not merely rows that agree on selected fields. -/
theorem CompleteProgramElaboration.symbolicVariantConstructor_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (leftSelected : SelectsSymbolicVariantConstructor symbolic path left)
    (rightSelected : SelectsSymbolicVariantConstructor symbolic path right) :
    left = right :=
  selectsSymbolicVariantConstructor_unique complete.metadataUnique
    leftSelected rightSelected

/-- A value path cannot simultaneously denote a function and an enum-variant
    constructor. Both selections resolve the same value-namespace declaration,
    while complete collection proves that function metadata originates at an
    item occurrence and variant metadata at an enum-child occurrence. Catalog
    declaration-ID uniqueness makes those incompatible provenances collide. -/
theorem CompleteProgramElaboration.function_excludes_symbolicVariantConstructor
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (functionSelected : SourceWellFormed.SelectsFunction
      symbolic.scopeContext path scheme)
    (variantSelected : SelectsSymbolicVariantConstructor symbolic path constructor) :
    False := by
  rcases functionSelected with
    ⟨_functionNotShadowed, functionSymbol, functionResolved, functionMember,
      functionDeclaration, _functionUnique⟩
  rcases variantSelected with
    ⟨_variantNotShadowed, _globalNotShadowed, variantSymbol, variantResolved,
      variantMember, variantDeclaration, _variantUnique⟩
  have symbolDeclarationEquality :
      functionSymbol.declaration = variantSymbol.declaration :=
    functionResolved.declaration_unique variantResolved
  obtain ⟨_parentHeader, variantHeader, _nominal, _parentHeaderMember,
      variantHeaderMember, variantCollected⟩ :=
    complete.declarations.variantConstructorSchemes constructor variantMember
  obtain ⟨variantParent, variantIndex, variantSource,
      collectedVariantDeclaration⟩ := variantCollected.source_declaration
  have itemProvenanceImpossible :
      ∀ functionHeader, functionHeader ∈ catalog.headers →
        (∃ address, functionHeader.source = .item address ∧
          scheme.declaration = functionHeader.declaration) → False := by
    intro functionHeader functionHeaderMember functionProvenance
    obtain ⟨address, functionSource, collectedFunctionDeclaration⟩ :=
      functionProvenance
    have headerDeclarationEquality :
        functionHeader.declaration = variantHeader.declaration :=
      collectedFunctionDeclaration.symm.trans
        (functionDeclaration.trans
          (symbolDeclarationEquality.trans
            (variantDeclaration.symm.trans collectedVariantDeclaration)))
    have headerSourceEquality :
        functionHeader.source = variantHeader.source :=
      complete.declarationCatalog.2.1 functionHeader functionHeaderMember
        variantHeader variantHeaderMember headerDeclarationEquality
    have occurrenceContradiction :
        Declarations.DeclarationOccurrence.item address =
          .enumVariant variantParent variantIndex :=
      functionSource.symm.trans (headerSourceEquality.trans variantSource)
    cases occurrenceContradiction
  obtain ⟨functionHeader, _bodyContext, functionHeaderMember,
      functionCollected | externalCollected⟩ :=
    complete.declarations.functionSchemes scheme functionMember
  · exact itemProvenanceImpossible functionHeader functionHeaderMember
      functionCollected.source_declaration
  · exact itemProvenanceImpossible functionHeader functionHeaderMember
      externalCollected.source_declaration

/-- The four semantic categories available to a source path in call position.
    Generic-argument mode belongs to the selected category's elaboration and
    does not create another callee category. -/
inductive PathCallResolutionKind where
  | intrinsic
  | function
  | variant
  | associated
deriving DecidableEq

/-- Evidence for the category selected at one path-call occurrence. Intrinsic
    precedence is explicit for both kinds of global value; declaration
    provenance separates functions from enum constructors. -/
inductive PathCallResolvesAs
    (symbolic : SymbolicBodyContext) (path : Surface.Path) :
    PathCallResolutionKind → Prop where
  | intrinsic
      (found : SurfaceElaboration.builtinIntrinsic? path = some intrinsic) :
      PathCallResolvesAs symbolic path .intrinsic
  | function
      (selected : SourceWellFormed.SelectsFunction
        symbolic.scopeContext path scheme)
      (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
      PathCallResolvesAs symbolic path .function
  | variant
      (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
      (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
      PathCallResolvesAs symbolic path .variant
  | associated
      (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
      (notFunction : ¬ ∃ scheme,
        SourceWellFormed.SelectsFunction symbolic.scopeContext path scheme)
      (notVariant : ¬ ∃ constructor,
        SelectsSymbolicVariantConstructor symbolic path constructor) :
      PathCallResolvesAs symbolic path .associated

/-- One path-call occurrence has one callee category. This theorem centralizes
    intrinsic precedence and declaration-category disjointness so recursive
    expression functionality never needs a matrix of cross-category cases. -/
theorem PathCallResolvesAs.unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : PathCallResolvesAs symbolic path leftKind)
    (right : PathCallResolvesAs symbolic path rightKind) :
    leftKind = rightKind := by
  cases left with
  | intrinsic leftFound =>
      cases right with
      | intrinsic rightFound => rfl
      | function _selected rightNotIntrinsic =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            leftFound rightNotIntrinsic).elim
      | variant _selected rightNotIntrinsic =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            leftFound rightNotIntrinsic).elim
      | associated rightNotIntrinsic _ _ =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            leftFound rightNotIntrinsic).elim
  | function leftSelected leftNotIntrinsic =>
      cases right with
      | intrinsic rightFound =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            rightFound leftNotIntrinsic).elim
      | function _rightSelected _rightNotIntrinsic => rfl
      | variant rightSelected _rightNotIntrinsic =>
          exact (complete.function_excludes_symbolicVariantConstructor
            leftSelected rightSelected).elim
      | associated _ rightNotFunction _ =>
          exact (rightNotFunction ⟨_, leftSelected⟩).elim
  | variant leftSelected leftNotIntrinsic =>
      cases right with
      | intrinsic rightFound =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            rightFound leftNotIntrinsic).elim
      | function rightSelected _rightNotIntrinsic =>
          exact (complete.function_excludes_symbolicVariantConstructor
            rightSelected leftSelected).elim
      | variant _rightSelected _rightNotIntrinsic => rfl
      | associated _ _ rightNotVariant =>
          exact (rightNotVariant ⟨_, leftSelected⟩).elim
  | associated leftNotIntrinsic leftNotFunction leftNotVariant =>
      cases right with
      | intrinsic rightFound =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            rightFound leftNotIntrinsic).elim
      | function rightSelected _ =>
          exact (leftNotFunction ⟨_, rightSelected⟩).elim
      | variant rightSelected _ =>
          exact (leftNotVariant ⟨_, rightSelected⟩).elim
      | associated _ _ _ => rfl

/-- Every exact path-call derivation exposes its semantic callee category. -/
theorem ExprInferenceDerivationSpecializes.pathCallResolution
    (derived : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      symbolicType groundType coreExpression) :
    ∃ kind, PathCallResolvesAs symbolic path kind := by
  cases derived with
  | printI32 builtin argument => exact ⟨.intrinsic, .intrinsic builtin⟩
  | assert builtin argument => exact ⟨.intrinsic, .intrinsic builtin⟩
  | i32ArrayDataPtr builtin argument => exact ⟨.intrinsic, .intrinsic builtin⟩
  | variantExplicit evidence payload =>
      exact ⟨.variant, .variant evidence.selected evidence.notIntrinsic⟩
  | variantInferred evidence payload =>
      exact ⟨.variant, .variant evidence.selected evidence.notIntrinsic⟩
  | variantNongeneric evidence payload =>
      exact ⟨.variant, .variant evidence.selected evidence.notIntrinsic⟩
  | directCallInferred evidence arguments =>
      exact ⟨.function, .function evidence.selected evidence.notIntrinsic⟩
  | directCallExplicit evidence arguments =>
      exact ⟨.function, .function evidence.selected evidence.notIntrinsic⟩
  | directCallNongeneric evidence arguments =>
      exact ⟨.function, .function evidence.selected evidence.notIntrinsic⟩
  | associatedCallInferred evidence arguments =>
      exact ⟨.associated, .associated evidence.notIntrinsic
        evidence.notFunction evidence.notVariant⟩
  | associatedCallContextual evidence arguments =>
      exact ⟨.associated, .associated evidence.notIntrinsic
        evidence.notFunction evidence.notVariant⟩

/-- Within a complete program, one source struct path selects one full
    constructor scheme, not merely rows agreeing on their projected fields. -/
theorem CompleteProgramElaboration.structConstructor_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      context externalBindings)
    (leftSelected : SurfaceElaboration.SelectsStructConstructor context path left)
    (rightSelected : SurfaceElaboration.SelectsStructConstructor context path right) :
    left = right :=
  selectsStructConstructor_unique complete.metadataUnique leftSelected rightSelected

/-- A complete program gives symbolic field lookup one result type. The proof
    first fixes the struct constructor by source `TypeId`, then the named field,
    and finally uses collection provenance to show that equal ordered generic
    arguments substitute its retained type identically. -/
theorem CompleteProgramElaboration.symbolicFieldResult_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (leftSelected : SelectsSymbolicField symbolic receiver name leftResult)
    (rightSelected : SelectsSymbolicField symbolic receiver name rightResult) :
    leftResult = rightResult := by
  rcases leftSelected with
    ⟨leftSourceType, leftTypeArguments, leftConstArguments, leftConstructor,
      leftSubstitution, leftField, leftReceiver, leftConstructorMember,
      leftConstructorType, leftArguments, leftFieldMember, leftFieldName,
      leftSubstituted, leftFieldUnique⟩
  rcases rightSelected with
    ⟨rightSourceType, rightTypeArguments, rightConstArguments, rightConstructor,
      rightSubstitution, rightField, rightReceiver, rightConstructorMember,
      rightConstructorType, rightArguments, rightFieldMember, rightFieldName,
      rightSubstituted, _rightFieldUnique⟩
  have receiverEquality := leftReceiver.symm.trans rightReceiver
  injection receiverEquality with sourceTypeEquality typeArgumentsEquality
    constArgumentsEquality
  have constructorKeyEquality :
      leftConstructor.sourceType = rightConstructor.sourceType :=
    leftConstructorType.trans
      (sourceTypeEquality.trans rightConstructorType.symm)
  subst rightTypeArguments
  subst rightConstArguments
  have constructorEquality :=
    complete.metadataUnique.structConstructorSourceTypes
      leftConstructor leftConstructorMember rightConstructor
      rightConstructorMember constructorKeyEquality
  subst rightConstructor
  have fieldEquality :=
    leftFieldUnique rightField rightFieldMember rightFieldName
  subst rightField
  obtain ⟨header, nominal, _headerMember, collected⟩ :=
    complete.declarations.structConstructorSchemes leftConstructor
      leftConstructorMember
  exact collected.field_substitute_unique leftFieldMember leftArguments
    rightArguments leftSubstituted rightSubstituted

/-- Exact inference of a value path is functional. In particular, the
    shadowing rule makes the local and constant constructors disjoint rather
    than relying on rule order. -/
theorem CompleteProgramElaboration.pathInference_unique
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.path path) leftType leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.path path) rightType rightGround rightCore) :
    leftType = rightType ∧ leftGround = rightGround ∧ leftCore = rightCore := by
  cases left with
  | «local» leftSingle leftSymbolicResolved leftConcreteResolved leftGrounds =>
      cases right with
      | «local» rightSingle rightSymbolicResolved rightConcreteResolved
          rightGrounds =>
          have nameEquality := Option.some.inj
            (leftSingle.symm.trans rightSingle)
          subst nameEquality
          cases leftSymbolicResolved.unique rightSymbolicResolved
          cases leftConcreteResolved.unique rightConcreteResolved
          exact ⟨rfl, rfl, rfl⟩
      | constant rightSymbolicSelected rightConcreteSelected =>
          exact (rightSymbolicSelected.1.excludesLocal leftSingle
            leftSymbolicResolved.scopeResolved).elim
  | constant leftSymbolicSelected leftConcreteSelected =>
      cases right with
      | «local» rightSingle rightSymbolicResolved rightConcreteResolved
          rightGrounds =>
          exact (leftSymbolicSelected.1.excludesLocal rightSingle
            rightSymbolicResolved.scopeResolved).elim
      | constant rightSymbolicSelected rightConcreteSelected =>
          cases leftSymbolicSelected.unique rightSymbolicSelected
          exact ⟨rfl, rfl, rfl⟩

/-- Default literal inference has one core value. -/
theorem ExprInferenceDerivationSpecializes.literal_unique
    {surfaceLiteral : Surface.Literal}
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.literal surfaceLiteral) leftType leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.literal surfaceLiteral) rightType rightGround rightCore) :
    leftType = rightType ∧ leftGround = rightGround ∧ leftCore = rightCore := by
  cases left with
  | literal leftLowered =>
      cases right with
      | literal rightLowered =>
          cases leftLowered.core_unique rightLowered
          exact ⟨rfl, rfl, rfl⟩

/-- Literals infer only their language-defined default scalar type. Raw-pointer
    null literals therefore exist exclusively in contextual checking rules. -/
theorem ExprInferenceDerivationSpecializes.literal_not_raw_pointer
    {literal : Surface.Literal}
    (inferred : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.literal literal) (.scalar .rawPtr)
      groundType coreExpression) : False := by
  cases literal <;> cases inferred

/-- `self` is ordinary nearest-binding lookup with a distinguished source
    spelling, so both its symbolic and concrete projections are functional. -/
theorem ExprInferenceDerivationSpecializes.selfValue_unique
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts .selfValue leftType leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts .selfValue rightType rightGround rightCore) :
    leftType = rightType ∧ leftGround = rightGround ∧ leftCore = rightCore := by
  cases left with
  | selfValue leftSymbolicResolved leftConcreteResolved leftGrounds =>
      cases right with
      | selfValue rightSymbolicResolved rightConcreteResolved rightGrounds =>
          cases leftSymbolicResolved.unique rightSymbolicResolved
          cases leftConcreteResolved.unique rightConcreteResolved
          exact ⟨rfl, rfl, rfl⟩

/-- Exact value indexing is functional once exact inference is functional for
    its base and index children. Equality of the inferred base type also makes
    the array and slice rules disjoint. -/
theorem ExprInferenceDerivationSpecializes.index_unique_of_expr
    (baseUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (indexUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceIndex leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceIndex rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.index surfaceBase surfaceIndex)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.index surfaceBase surfaceIndex)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | indexArray leftBase leftElementGrounds leftIndex leftInteger =>
      cases right with
      | indexArray rightBase rightElementGrounds rightIndex rightInteger =>
          rcases baseUnique leftBase rightBase with
            ⟨baseTypeEquality, baseGroundEquality, coreBaseEquality⟩
          injection baseTypeEquality with elementTypeEquality lengthEquality
          injection baseGroundEquality with groundElementEquality
            groundLengthEquality
          cases elementTypeEquality
          cases lengthEquality
          cases groundElementEquality
          cases groundLengthEquality
          cases coreBaseEquality
          rcases indexUnique leftIndex rightIndex with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | indexSlice rightBase rightElementGrounds rightIndex rightInteger =>
          rcases baseUnique leftBase rightBase with ⟨baseTypeEquality, _, _⟩
          cases baseTypeEquality
  | indexSlice leftBase leftElementGrounds leftIndex leftInteger =>
      cases right with
      | indexArray rightBase rightElementGrounds rightIndex rightInteger =>
          rcases baseUnique leftBase rightBase with ⟨baseTypeEquality, _, _⟩
          cases baseTypeEquality
      | indexSlice rightBase rightElementGrounds rightIndex rightInteger =>
          rcases baseUnique leftBase rightBase with
            ⟨baseTypeEquality, baseGroundEquality, coreBaseEquality⟩
          injection baseTypeEquality with elementTypeEquality
          injection baseGroundEquality with groundElementEquality
          cases elementTypeEquality
          cases groundElementEquality
          cases coreBaseEquality
          rcases indexUnique leftIndex rightIndex with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

/-- Exact field inference is functional once its base expression is. The
    normalized symbolic receiver is explicitly grounded to the receiver used
    by concrete member lowering, so symbolic and concrete field selection
    cannot drift to unrelated rows. -/
theorem ExprInferenceDerivationSpecializes.field_unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (baseUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.member surfaceBase name) leftSymbolic
      leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.member surfaceBase name) rightSymbolic
      rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | field leftBase leftMemberBase leftMemberLowers leftReceiverGrounds
      leftSymbolicSelected leftConcreteSelected leftFieldGrounds =>
      cases right with
      | field rightBase rightMemberBase rightMemberLowers rightReceiverGrounds
          rightSymbolicSelected rightConcreteSelected rightFieldGrounds =>
          rcases baseUnique leftBase rightBase with
            ⟨sourceTypeEquality, sourceGroundEquality, sourceCoreEquality⟩
          cases sourceTypeEquality
          cases sourceGroundEquality
          cases sourceCoreEquality
          cases leftMemberBase.unique rightMemberBase
          have receiverGroundEquality := Option.some.inj
            (leftReceiverGrounds.symm.trans rightReceiverGrounds)
          cases receiverGroundEquality
          cases leftMemberLowers.core_unique rightMemberLowers
          cases complete.symbolicFieldResult_unique leftSymbolicSelected
            rightSymbolicSelected
          cases leftConcreteSelected.unique rightConcreteSelected
          exact ⟨rfl, rfl, rfl⟩

/-- Exact unary inference is functional once its operand is. The exceptional
    signed-minimum rule is disjoint from ordinary unary negation because that
    magnitude cannot elaborate as a positive operand of the same signed type. -/
theorem ExprInferenceDerivationSpecializes.unary_unique_of_expr
    (operandUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceOperand leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceOperand rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.unary op surfaceOperand) leftSymbolic
      leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.unary op surfaceOperand) rightSymbolic
      rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | signedMinimumLiteral leftMinimum =>
      cases right with
      | signedMinimumLiteral rightMinimum =>
          cases leftMinimum.core_unique rightMinimum
          exact ⟨rfl, rfl, rfl⟩
      | unaryScalar rightOperand rightTyped =>
          cases rightOperand with
          | literal rightPositive =>
              exact (leftMinimum.not_positive_literal rightPositive).elim
  | unaryScalar leftOperand leftTyped =>
      cases right with
      | signedMinimumLiteral rightMinimum =>
          cases leftOperand with
          | literal leftPositive =>
              exact (rightMinimum.not_positive_literal leftPositive).elim
      | unaryScalar rightOperand rightTyped =>
          rcases operandUnique leftOperand rightOperand with
            ⟨inputTypeEquality, inputGroundEquality, coreOperandEquality⟩
          injection inputTypeEquality with scalarTypeEquality
          injection inputGroundEquality with groundScalarTypeEquality
          cases scalarTypeEquality
          cases groundScalarTypeEquality
          cases coreOperandEquality
          have outputTypeEquality := leftTyped.output_unique rightTyped
          injection outputTypeEquality with scalarOutputEquality
          cases scalarOutputEquality
          exact ⟨rfl, rfl, rfl⟩

/-- Two ordinary binary-operation derivations agree once their recursively
    inferred operands do. -/
private theorem binaryOperationDerivations_unique_of_expr
    (leftUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceLeft leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceLeft rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (rightUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceRight leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceRight rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (leftLeft : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaceLeft (.scalar leftLeftType)
      (.scalar leftLeftType) leftCoreLeft)
    (leftRight : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaceRight (.scalar leftRightType)
      (.scalar leftRightType) leftCoreRight)
    (leftOperation : BinaryOperationSpecializes op leftLeftType leftRightType
      leftCoreLeft leftCoreRight leftOutput leftCore)
    (rightLeft : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaceLeft (.scalar rightLeftType)
      (.scalar rightLeftType) rightCoreLeft)
    (rightRight : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaceRight (.scalar rightRightType)
      (.scalar rightRightType) rightCoreRight)
    (rightOperation : BinaryOperationSpecializes op rightLeftType rightRightType
      rightCoreLeft rightCoreRight rightOutput rightCore) :
    leftOutput = rightOutput ∧ leftCore = rightCore := by
  rcases leftUnique leftLeft rightLeft with
    ⟨leftTypeEquality, leftGroundEquality, leftCoreEquality⟩
  injection leftTypeEquality with leftScalarEquality
  injection leftGroundEquality with leftGroundScalarEquality
  cases leftScalarEquality
  cases leftGroundScalarEquality
  cases leftCoreEquality
  rcases rightUnique leftRight rightRight with
    ⟨rightTypeEquality, rightGroundEquality, rightCoreEquality⟩
  injection rightTypeEquality with rightScalarEquality
  injection rightGroundEquality with rightGroundScalarEquality
  cases rightScalarEquality
  cases rightGroundScalarEquality
  cases rightCoreEquality
  rcases leftOperation.unique rightOperation with
    ⟨outputEquality, coreEquality⟩
  exact ⟨outputEquality, coreEquality⟩

private theorem scalarInference_aligns_with_rawPointer
    (surfaceUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (scalar : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.scalar scalarType)
      (.scalar scalarType) scalarCore)
    (pointer : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.scalar .rawPtr) (.scalar .rawPtr)
      pointerCore) :
    scalarType = .rawPtr ∧ scalarCore = pointerCore := by
  rcases surfaceUnique scalar pointer with
    ⟨typeEquality, _groundEquality, coreEquality⟩
  injection typeEquality with scalarEquality
  exact ⟨scalarEquality, coreEquality⟩

private theorem rawPointerInference_core_unique
    (surfaceUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.scalar .rawPtr) (.scalar .rawPtr)
      leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.scalar .rawPtr) (.scalar .rawPtr)
      rightCore) :
    leftCore = rightCore := (surfaceUnique left right).2.2

/-- Exact binary inference is functional. Ordinary coercion modes emit one
    cast placement, contextual null-pointer literals are disjoint from ordinary
    `i32` literal inference, and the left-null and right-null rules cannot both
    apply to one occurrence. -/
theorem ExprInferenceDerivationSpecializes.binary_unique_of_expr
    (leftUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceLeft leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceLeft rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (rightUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceRight leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceRight rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.binary op surfaceLeft surfaceRight)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.binary op surfaceLeft surfaceRight)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | binaryExact leftLeft leftRight leftTyped =>
      cases right with
      | binaryExact rightLeft rightRight rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.exact leftTyped) rightLeft rightRight
              (.exact rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryNullPointerRight rightPointer rightNull rightTyped =>
          cases leftRight with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique leftLeft
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.exact leftTyped)
                |>.incompatible_with_null_right rightTyped).elim
      | binaryNullPointerLeft rightNull rightPointer rightTyped =>
          cases leftLeft with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique leftRight
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.exact leftTyped)
                |>.incompatible_with_null_left rightTyped).elim
      | binaryRightCast rightLeft rightRight rightDifferent rightNotPreferred
          rightConversion rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.exact leftTyped) rightLeft rightRight
              (.rightCast rightDifferent rightNotPreferred rightConversion
                rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryLeftCast rightLeft rightRight rightPreferred rightConversion
          rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.exact leftTyped) rightLeft rightRight
              (.leftCast rightPreferred rightConversion rightTyped) with
            ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
  | binaryNullPointerRight leftPointer leftNull leftTyped =>
      cases right with
      | binaryExact rightLeft rightRight rightTyped =>
          cases rightRight with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique rightLeft
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.exact rightTyped)
                |>.incompatible_with_null_right leftTyped).elim
      | binaryNullPointerRight rightPointer rightNull rightTyped =>
          cases rawPointerInference_core_unique leftUnique leftPointer rightPointer
          cases leftNull.core_unique rightNull
          have outputEquality := leftTyped.output_unique rightTyped
          injection outputEquality with scalarEquality
          cases scalarEquality
          exact ⟨rfl, rfl, rfl⟩
      | binaryNullPointerLeft rightNull rightPointer rightTyped =>
          exact leftPointer.literal_not_raw_pointer.elim
      | binaryRightCast rightLeft rightRight rightDifferent rightNotPreferred
          rightConversion rightTyped =>
          cases rightRight with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique rightLeft
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.rightCast rightDifferent
                rightNotPreferred rightConversion rightTyped)
                |>.incompatible_with_null_right leftTyped).elim
      | binaryLeftCast rightLeft rightRight rightPreferred rightConversion
          rightTyped =>
          cases rightRight with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique rightLeft
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.leftCast rightPreferred
                rightConversion rightTyped)
                |>.incompatible_with_null_right leftTyped).elim
  | binaryNullPointerLeft leftNull leftPointer leftTyped =>
      cases right with
      | binaryExact rightLeft rightRight rightTyped =>
          cases rightLeft with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique rightRight
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.exact rightTyped)
                |>.incompatible_with_null_left leftTyped).elim
      | binaryNullPointerRight rightPointer rightNull rightTyped =>
          exact rightPointer.literal_not_raw_pointer.elim
      | binaryNullPointerLeft rightNull rightPointer rightTyped =>
          cases leftNull.core_unique rightNull
          cases rawPointerInference_core_unique rightUnique leftPointer rightPointer
          have outputEquality := leftTyped.output_unique rightTyped
          injection outputEquality with scalarEquality
          cases scalarEquality
          exact ⟨rfl, rfl, rfl⟩
      | binaryRightCast rightLeft rightRight rightDifferent rightNotPreferred
          rightConversion rightTyped =>
          cases rightLeft with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique rightRight
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.rightCast rightDifferent
                rightNotPreferred rightConversion rightTyped)
                |>.incompatible_with_null_left leftTyped).elim
      | binaryLeftCast rightLeft rightRight rightPreferred rightConversion
          rightTyped =>
          cases rightLeft with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique rightRight
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.leftCast rightPreferred
                rightConversion rightTyped)
                |>.incompatible_with_null_left leftTyped).elim
  | binaryRightCast leftLeft leftRight leftDifferent leftNotPreferred
      leftConversion leftTyped =>
      cases right with
      | binaryExact rightLeft rightRight rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.rightCast leftDifferent leftNotPreferred
                leftConversion leftTyped) rightLeft rightRight
              (.exact rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryNullPointerRight rightPointer rightNull rightTyped =>
          cases leftRight with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique leftLeft
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.rightCast leftDifferent
                leftNotPreferred leftConversion leftTyped)
                |>.incompatible_with_null_right rightTyped).elim
      | binaryNullPointerLeft rightNull rightPointer rightTyped =>
          cases leftLeft with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique leftRight
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.rightCast leftDifferent
                leftNotPreferred leftConversion leftTyped)
                |>.incompatible_with_null_left rightTyped).elim
      | binaryRightCast rightLeft rightRight rightDifferent rightNotPreferred
          rightConversion rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.rightCast leftDifferent leftNotPreferred
                leftConversion leftTyped) rightLeft rightRight
              (.rightCast rightDifferent rightNotPreferred rightConversion
                rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryLeftCast rightLeft rightRight rightPreferred rightConversion
          rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.rightCast leftDifferent leftNotPreferred
                leftConversion leftTyped) rightLeft rightRight
              (.leftCast rightPreferred rightConversion rightTyped) with
            ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
  | binaryLeftCast leftLeft leftRight leftPreferred leftConversion leftTyped =>
      cases right with
      | binaryExact rightLeft rightRight rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.leftCast leftPreferred leftConversion leftTyped)
              rightLeft rightRight (.exact rightTyped) with
            ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryNullPointerRight rightPointer rightNull rightTyped =>
          cases leftRight with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique leftLeft
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.leftCast leftPreferred
                leftConversion leftTyped)
                |>.incompatible_with_null_right rightTyped).elim
      | binaryNullPointerLeft rightNull rightPointer rightTyped =>
          cases leftLeft with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique leftRight
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.leftCast leftPreferred
                leftConversion leftTyped)
                |>.incompatible_with_null_left rightTyped).elim
      | binaryRightCast rightLeft rightRight rightDifferent rightNotPreferred
          rightConversion rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.leftCast leftPreferred leftConversion leftTyped)
              rightLeft rightRight (.rightCast rightDifferent rightNotPreferred
                rightConversion rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryLeftCast rightLeft rightRight rightPreferred rightConversion
          rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.leftCast leftPreferred leftConversion leftTyped)
              rightLeft rightRight (.leftCast rightPreferred rightConversion
                rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩

/-- Exact inference over an expression list is functional whenever exact
    inference of each element is functional. Keeping this structural list
    argument outside the generated mutual recursor avoids duplicating list
    traversal in every expression proof. -/
theorem ExprListInferenceDerivationSpecializes.unique_of_expr
    (exprUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprListInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces leftSymbolic leftGround leftCore)
    (right : ExprListInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  induction surfaces generalizing leftSymbolic leftGround leftCore
      rightSymbolic rightGround rightCore with
  | nil =>
      cases left
      cases right
      exact ⟨rfl, rfl, rfl⟩
  | cons surfaceHead surfaceTail induction =>
      cases left with
      | cons leftHead leftTail =>
          cases right with
          | cons rightHead rightTail =>
              rcases exprUnique leftHead rightHead with ⟨rfl, rfl, rfl⟩
              rcases induction leftTail rightTail with ⟨rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩

/-- Contextual checking over an expression list inherits functionality from
    checking one expression at a fixed expected symbolic type. -/
theorem ExprListCheckingDerivationSpecializes.unique_of_expr
    (exprUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprListCheckingDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces expectedTypes leftGround leftCore)
    (right : ExprListCheckingDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces expectedTypes rightGround rightCore) :
    leftGround = rightGround ∧ leftCore = rightCore := by
  induction surfaces generalizing expectedTypes leftGround leftCore rightGround
      rightCore with
  | nil =>
      cases left
      cases right
      exact ⟨rfl, rfl⟩
  | cons surfaceHead surfaceTail induction =>
      cases left with
      | cons leftHead leftTail =>
          cases right with
          | cons rightHead rightTail =>
              rcases exprUnique leftHead rightHead with ⟨rfl, rfl⟩
              rcases induction leftTail rightTail with ⟨rfl, rfl⟩
              exact ⟨rfl, rfl⟩

/-- Checking the same expression against arrays with one fixed element type
    determines the source length as well as the ground type and emitted Core.
    This covers both exact inference and contextual array checking, so clients
    such as `i32_array_data_ptr` do not need to choose a checking mode first. -/
theorem ExprCheckingDerivationSpecializes.array_unique_of_expr
    (inferUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprCheckingDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.array elementType leftLength)
      leftGround leftCore)
    (right : ExprCheckingDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.array elementType rightLength)
      rightGround rightCore) :
    leftLength = rightLength ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | exact leftInferred _leftSymbolic _leftGrounds _leftConcrete =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          rcases inferUnique leftInferred rightInferred with
            ⟨typeEquality, groundEquality, coreEquality⟩
          injection typeEquality with _elementEquality lengthEquality
          exact ⟨lengthEquality, groundEquality, coreEquality⟩
      | array rightElements rightElementGrounds rightElementCore =>
          cases leftInferred with
          | array leftHead leftTail leftElementCore =>
              have leftCheck :=
                (ExprInferenceDerivationSpecializes.array leftHead leftTail
                  leftElementCore).asChecking
              have rightCheck :=
                ExprCheckingDerivationSpecializes.array rightElements
                  rightElementGrounds rightElementCore
              obtain ⟨groundEquality, coreEquality⟩ :=
                checkUnique leftCheck rightCheck
              exact ⟨rfl, groundEquality, coreEquality⟩
      | structValue _selected expected _arguments _typeArgumentsGround
          _constArgumentsGround _pathArguments _requirements _artifact _fields
          _symbolicFields _concreteFields =>
          cases expected
      | variantCall _selected _notIntrinsic expected _arguments
          _typeArgumentsGround _constArgumentsGround _pathArguments
          _requirements _artifact _payload _symbolicPayload _concretePayload =>
          cases expected
  | array leftElements leftElementGrounds leftElementCore =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          cases rightInferred with
          | array rightHead rightTail rightElementCore' =>
              have leftCheck :=
                ExprCheckingDerivationSpecializes.array leftElements
                  leftElementGrounds leftElementCore
              have rightCheck :=
                (ExprInferenceDerivationSpecializes.array rightHead rightTail
                  rightElementCore').asChecking
              obtain ⟨groundEquality, coreEquality⟩ :=
                checkUnique leftCheck rightCheck
              exact ⟨rfl, groundEquality, coreEquality⟩
      | array rightElements rightElementGrounds rightElementCore =>
          have groundElementEquality := Option.some.inj
            (leftElementGrounds.symm.trans rightElementGrounds)
          cases groundElementEquality
          have coreElementEquality := Option.some.inj
            (leftElementCore.symm.trans rightElementCore)
          cases coreElementEquality
          have leftCheck := ExprCheckingDerivationSpecializes.array leftElements
            leftElementGrounds leftElementCore
          have rightCheck := ExprCheckingDerivationSpecializes.array rightElements
            rightElementGrounds rightElementCore
          obtain ⟨groundEquality, coreEquality⟩ :=
            checkUnique leftCheck rightCheck
          exact ⟨rfl, groundEquality, coreEquality⟩
  | structValue _selected expected _arguments _typeArgumentsGround
      _constArgumentsGround _pathArguments _requirements _artifact _fields
      _symbolicFields _concreteFields =>
      cases expected
  | variantCall _selected _notIntrinsic expected _arguments
      _typeArgumentsGround _constArgumentsGround _pathArguments _requirements
      _artifact _payload _symbolicPayload _concretePayload =>
      cases expected

/-- A reserved intrinsic path-call has one exact result. The path fixes which
    intrinsic applies; ordinary functions and variants are unavailable by
    intrinsic precedence. Array-pointer calls additionally use contextual
    array functionality to recover their otherwise existential length. -/
theorem ExprInferenceDerivationSpecializes.intrinsicPathCall_unique_of_expr
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (resolved : PathCallResolvesAs symbolic path .intrinsic)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases resolved with
  | intrinsic found =>
      cases left with
      | printI32 leftBuiltin leftArgument =>
          cases right with
          | printI32 _rightBuiltin rightArgument =>
              obtain ⟨_groundEquality, coreEquality⟩ :=
                checkUnique leftArgument rightArgument
              exact ⟨rfl, rfl, congrArg
                (fun argument => Core.Expr.intrinsic .printI32 argument)
                coreEquality⟩
          | assert rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | i32ArrayDataPtr rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | variantExplicit evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantInferred evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantNongeneric evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallExplicit evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallNongeneric evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallContextual evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
      | assert leftBuiltin leftArgument =>
          cases right with
          | printI32 rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | assert _rightBuiltin rightArgument =>
              obtain ⟨_groundEquality, coreEquality⟩ :=
                checkUnique leftArgument rightArgument
              exact ⟨rfl, rfl, congrArg
                (fun argument => Core.Expr.intrinsic .assert argument)
                coreEquality⟩
          | i32ArrayDataPtr rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | variantExplicit evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantInferred evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantNongeneric evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallExplicit evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallNongeneric evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallContextual evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
      | i32ArrayDataPtr leftBuiltin leftArgument =>
          cases right with
          | printI32 rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | assert rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | i32ArrayDataPtr _rightBuiltin rightArgument =>
              obtain ⟨_lengthEquality, _groundEquality, coreEquality⟩ :=
                ExprCheckingDerivationSpecializes.array_unique_of_expr
                  inferUnique checkUnique leftArgument rightArgument
              exact ⟨rfl, rfl, congrArg Core.Expr.i32ArrayDataPtr coreEquality⟩
          | variantExplicit evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantInferred evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantNongeneric evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallExplicit evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallNongeneric evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallContextual evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
      | variantExplicit evidence _payload =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | variantInferred evidence _payload =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | variantNongeneric evidence _payload =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | directCallInferred evidence _arguments =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | directCallExplicit evidence _arguments =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | directCallNongeneric evidence _arguments =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | associatedCallInferred evidence _arguments =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | associatedCallContextual evidence _arguments =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim

/-- Nonempty array inference is functional once inference of its head and
    contextual checking of its tail are functional. The Core element type is
    also fixed because ground-type lowering is an ordinary function. -/
theorem ExprInferenceDerivationSpecializes.array_unique_of_expr
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.array surfaceElements) leftSymbolic
      leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.array surfaceElements) rightSymbolic
      rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | array leftHead leftTail leftElementCore =>
      cases right with
      | array rightHead rightTail rightElementCore =>
          rcases inferUnique leftHead rightHead with ⟨rfl, rfl, rfl⟩
          obtain ⟨_groundTailEquality, coreTailEquality⟩ :=
            ExprListCheckingDerivationSpecializes.unique_of_expr checkUnique
              leftTail rightTail
          cases coreTailEquality
          have coreElementEquality := Option.some.inj
            (leftElementCore.symm.trans rightElementCore)
          cases coreElementEquality
          exact ⟨rfl, rfl, rfl⟩

/-- Substituted argument checking has no hidden choice: substitution is a
    function, each checked head is functional, and the tail is structural. -/
theorem ExprListSubstitutedCheckingDerivationSpecializes.unique_of_expr
    (exprUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner surfaces
      originalTypes leftCore)
    (right : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner surfaces
      originalTypes rightCore) :
    leftCore = rightCore := by
  induction surfaces generalizing originalTypes leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons surfaceHead surfaceTail induction =>
      cases left with
      | cons leftSubstituted leftHead leftTail _leftSymbolic _leftConcrete =>
          cases right with
          | cons rightSubstituted rightHead rightTail _rightSymbolic
              _rightConcrete =>
              have expectedEquality := Option.some.inj
                (leftSubstituted.symm.trans rightSubstituted)
              cases expectedEquality
              rcases exprUnique leftHead rightHead with ⟨rfl, rfl⟩
              cases induction leftTail rightTail
              rfl

theorem ExprListSubstitutedCheckingDerivationSpecializes.substitutedTypes
    (derivation : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner surfaces
      originalTypes cores) :
    ∃ expectedTypes,
      Static.substituteTypes inner originalTypes = some expectedTypes := by
  induction originalTypes generalizing surfaces cores with
  | nil =>
      cases derivation
      exact ⟨[], rfl⟩
  | cons originalHead originalTail induction =>
      cases derivation with
      | cons substituted head tail _tailSymbolic _tailConcrete =>
          rename_i expectedHead surfaceHead groundHead coreHead surfaceTail
            coreTail
          obtain ⟨tailTypes, tailSubstituted⟩ := induction tail
          exact ⟨expectedHead :: tailTypes, by
            simp [Static.substituteTypes, substituted, tailSubstituted]⟩

/-- Substituted list checking depends only on the substituted expected-type
    list, not on unrelated entries in the two substitution maps. -/
theorem ExprListSubstitutedCheckingDerivationSpecializes.unique_of_expr_and_substitution
    (exprUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner surfaces
      originalTypes leftCore)
    (right : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner surfaces
      originalTypes rightCore)
    (substitutionsAgree : Static.substituteTypes leftInner originalTypes =
      Static.substituteTypes rightInner originalTypes) :
    leftCore = rightCore := by
  induction originalTypes generalizing surfaces leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons originalHead originalTail induction =>
      cases left with
      | cons leftSubstituted leftHead leftTail _leftSymbolic _leftConcrete =>
          cases right with
          | cons rightSubstituted rightHead rightTail _rightSymbolic
              _rightConcrete =>
              rename_i leftExpectedHead surfaceHead leftGroundHead leftCoreHead
                surfaceTail leftCoreTail rightExpectedHead rightGroundHead
                rightCoreHead rightCoreTail
              obtain ⟨leftTailTypes, leftTailSubstituted⟩ :=
                leftTail.substitutedTypes
              obtain ⟨rightTailTypes, rightTailSubstituted⟩ :=
                rightTail.substitutedTypes
              have expectedListsEquality :
                  leftExpectedHead :: leftTailTypes =
                    rightExpectedHead :: rightTailTypes := by
                have sameSome : some (leftExpectedHead :: leftTailTypes) =
                    some (rightExpectedHead :: rightTailTypes) := by
                  simpa [Static.substituteTypes, leftSubstituted,
                    rightSubstituted, leftTailSubstituted,
                    rightTailSubstituted] using substitutionsAgree
                exact Option.some.inj sameSome
              injection expectedListsEquality with headEquality tailEquality
              cases headEquality
              cases tailEquality
              rcases exprUnique leftHead rightHead with ⟨rfl, rfl⟩
              have tailSubstitutionsAgree :
                  Static.substituteTypes leftInner originalTail =
                    Static.substituteTypes rightInner originalTail :=
                leftTailSubstituted.trans rightTailSubstituted.symm
              cases induction leftTail rightTail tailSubstitutionsAgree
              rfl

/-- Named struct-field checking is functional once expression checking is:
    first-match field removal and retained-type substitution are themselves
    functions. -/
theorem StructFieldsCheckingDerivationSpecializes.unique_of_expr
    (exprUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner fields
      surfaceFields leftCore)
    (right : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner fields
      surfaceFields rightCore) :
    leftCore = rightCore := by
  induction fields generalizing surfaceFields leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons field fieldTail induction =>
      cases left with
      | cons leftRemoved leftSubstituted leftValue leftTail _leftSymbolic
          _leftConcrete =>
          cases right with
          | cons rightRemoved rightSubstituted rightValue rightTail
              _rightSymbolic _rightConcrete =>
              rcases leftRemoved.unique rightRemoved with ⟨rfl, rfl⟩
              have expectedEquality := Option.some.inj
                (leftSubstituted.symm.trans rightSubstituted)
              cases expectedEquality
              rcases exprUnique leftRemoved.selected_mem leftValue rightValue with
                ⟨rfl, rfl⟩
              cases induction (fun member =>
                  exprUnique (leftRemoved.remainder_subset _ member))
                leftTail rightTail
              rfl

/-- Struct-field checking remains functional across two substitution maps that
    bind the same ordered constructor arguments. Complete declaration
    provenance ensures every retained field type substitutes identically. -/
theorem StructFieldsCheckingDerivationSpecializes.unique_of_expr_and_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (exprUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (constructorMember : constructor ∈ symbolic.globals.structConstructors)
    (fieldsBelong : ∀ field, field ∈ fields → field ∈ constructor.fields)
    (leftBound : Static.SymbolicArgumentsBound leftInner
      constructor.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightInner
      constructor.genericParameters typeArguments constArguments)
    (left : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner fields
      surfaceFields leftCore)
    (right : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner fields
      surfaceFields rightCore) :
    leftCore = rightCore := by
  induction fields generalizing surfaceFields leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons field fieldTail induction =>
      cases left with
      | cons leftRemoved leftSubstituted leftValue leftTail _leftSymbolic
          _leftConcrete =>
          cases right with
          | cons rightRemoved rightSubstituted rightValue rightTail
              _rightSymbolic _rightConcrete =>
              rcases leftRemoved.unique rightRemoved with ⟨rfl, rfl⟩
              have expectedEquality :=
                complete.structFieldSubstitute_unique constructorMember
                  (fieldsBelong field (by simp)) leftBound rightBound
                  leftSubstituted rightSubstituted
              cases expectedEquality
              rcases exprUnique leftRemoved.selected_mem leftValue rightValue with
                ⟨rfl, rfl⟩
              have tailBelongs : ∀ candidate,
                  candidate ∈ fieldTail → candidate ∈ constructor.fields := by
                intro candidate member
                exact fieldsBelong candidate (by simp [member])
              cases induction (fun member =>
                  exprUnique (leftRemoved.remainder_subset _ member)) tailBelongs
                leftTail rightTail
              rfl

/-- Named struct-field inference likewise reduces to functional first-match
    removal, functional expression inference, and the structural tail. -/
theorem StructFieldsInferenceDerivationSpecializes.unique_of_expr
    (exprUnique : ∀ {name surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner fields
      surfaceFields leftCore)
    (right : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner fields
      surfaceFields rightCore) :
    leftCore = rightCore := by
  induction fields generalizing surfaceFields leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons field fieldTail induction =>
      cases left with
      | cons leftRemoved leftValue leftMatched leftTail _leftSymbolic
          _leftConcrete =>
          cases right with
          | cons rightRemoved rightValue rightMatched rightTail _rightSymbolic
              _rightConcrete =>
              rcases leftRemoved.unique rightRemoved with ⟨rfl, rfl⟩
              rcases exprUnique leftRemoved.selected_mem leftValue rightValue with
                ⟨rfl, rfl, rfl⟩
              cases induction (fun member =>
                  exprUnique (leftRemoved.remainder_subset _ member))
                leftTail rightTail
              rfl

/-- Field inference and contextual field checking emit the same Core values
    when their constructor substitutions bind the same ordered arguments. The
    inferred match is converted to an exact check only after declaration
    provenance proves that its observed type is the contextual field type. -/
theorem StructFieldsInferenceDerivationSpecializes.core_unique_of_expr_and_checked
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (exprUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (constructorMember : constructor ∈ symbolic.globals.structConstructors)
    (fieldsBelong : ∀ field, field ∈ fields → field ∈ constructor.fields)
    (inferredBound : Static.SymbolicArgumentsBound inferredInner
      constructor.genericParameters typeArguments constArguments)
    (checkedBound : Static.SymbolicArgumentsBound checkedInner
      constructor.genericParameters typeArguments constArguments)
    (inferred : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inferredInner fields
      surfaceFields inferredCore)
    (checked : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts checkedInner fields
      surfaceFields checkedCore) :
    inferredCore = checkedCore := by
  induction fields generalizing surfaceFields inferredCore checkedCore with
  | nil =>
      cases inferred
      cases checked
      rfl
  | cons field fieldTail induction =>
      cases inferred with
      | cons inferredRemoved inferredValue inferredMatched inferredTail
          _inferredSymbolic _inferredConcrete =>
          cases checked with
          | cons checkedRemoved checkedSubstituted checkedValue checkedTail
              _checkedSymbolic _checkedConcrete =>
              rcases inferredRemoved.unique checkedRemoved with ⟨rfl, rfl⟩
              have expectedEquality :=
                complete.structFieldSubstitute_unique constructorMember
                  (fieldsBelong field (by simp)) inferredBound checkedBound
                  inferredMatched.substitutes checkedSubstituted
              cases expectedEquality
              rcases exprUnique inferredRemoved.selected_mem
                  inferredValue.asChecking checkedValue with ⟨rfl, rfl⟩
              have tailBelongs : ∀ candidate,
                  candidate ∈ fieldTail → candidate ∈ constructor.fields := by
                intro candidate member
                exact fieldsBelong candidate (by simp [member])
              cases induction
                (fun member => exprUnique
                  (inferredRemoved.remainder_subset _ member))
                tailBelongs inferredTail checkedTail
              rfl

/-- Two inferred field traversals expose matching derivations for the same
    declared field occurrence. This is the struct analogue of aligned list
    matching: named-field removal and recursive expression functionality first
    align the observed field type, after which the two substitutions can be
    compared on that occurrence. -/
theorem StructFieldsInferenceDerivationSpecializes.aligned_member_of_expr
    (exprUnique : ∀ {name surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner fields
      surfaceFields leftCore)
    (right : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner fields
      surfaceFields rightCore)
    (member : field ∈ fields) :
    ∃ actualType,
      Static.TySymbolicallyMatches leftInner field.type actualType ∧
      Static.TySymbolicallyMatches rightInner field.type actualType := by
  induction fields generalizing surfaceFields leftCore rightCore field with
  | nil => simp at member
  | cons fieldHead fieldTail induction =>
      cases left with
      | cons leftRemoved leftValue leftMatched leftTail _leftSymbolic
          _leftConcrete =>
          cases right with
          | cons rightRemoved rightValue rightMatched rightTail _rightSymbolic
              _rightConcrete =>
              rcases leftRemoved.unique rightRemoved with ⟨rfl, rfl⟩
              rcases exprUnique leftRemoved.selected_mem leftValue rightValue with
                ⟨rfl, rfl, rfl⟩
              simp only [List.mem_cons] at member
              rcases member with rfl | member
              · exact ⟨_, leftMatched, rightMatched⟩
              · exact induction
                  (fun selected =>
                    exprUnique (leftRemoved.remainder_subset _ selected))
                  leftTail rightTail member

/-- Field-driven inference fixes the ordered constructor arguments whenever
    the constructor's occurrence condition covers every generic parameter. -/
theorem StructFieldsInferenceDerivationSpecializes.orderedArguments_unique
    (exprUnique : ∀ {name surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (determined : SurfaceElaboration.TypesDetermineGenericParameters
      (fields.map fun field => field.type) parameters)
    (left : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner fields
      surfaceFields leftCore)
    (right : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner fields
      surfaceFields rightCore)
    (leftBound : Static.SymbolicArgumentsBound leftInner parameters
      leftTypeArguments leftConstArguments)
    (rightBound : Static.SymbolicArgumentsBound rightInner parameters
      rightTypeArguments rightConstArguments) :
    leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments := by
  apply leftBound.orderedArguments_unique_of_agreement rightBound
  · intro parameter parameterMember
    obtain ⟨pattern, patternMember, mentioned⟩ :=
      determined (.typeParameter parameter) parameterMember
    obtain ⟨field, fieldMember, fieldTypeEquality⟩ :=
      List.mem_map.mp patternMember
    cases fieldTypeEquality
    obtain ⟨_, leftMatched, rightMatched⟩ :=
      left.aligned_member_of_expr exprUnique right fieldMember
    exact mentioned.substitution_agrees leftMatched rightMatched
  · intro parameter parameterMember
    obtain ⟨pattern, patternMember, mentioned⟩ :=
      determined (.constParameter parameter) parameterMember
    obtain ⟨field, fieldMember, fieldTypeEquality⟩ :=
      List.mem_map.mp patternMember
    cases fieldTypeEquality
    obtain ⟨_, leftMatched, rightMatched⟩ :=
      left.aligned_member_of_expr exprUnique right fieldMember
    exact mentioned.substitution_agrees leftMatched rightMatched

/-- A generic struct occurrence inferred from its fields has one exact result:
    constructor identity, ordered symbolic arguments, monomorphic artifact, and
    emitted field expressions are all functional. -/
theorem StructInferenceEvidence.results_unique_of_fields
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (exprUnique : ∀ {name surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : StructInferenceEvidence outer concrete symbolic path leftConstructor
      leftInner leftTypeArguments leftConstArguments leftResolved)
    (right : StructInferenceEvidence outer concrete symbolic path rightConstructor
      rightInner rightTypeArguments rightConstArguments rightResolved)
    (leftFields : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      leftConstructor.fields surfaceFields leftCoreFields)
    (rightFields : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      rightConstructor.fields surfaceFields rightCoreFields) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧ leftCoreFields = rightCoreFields := by
  have constructorEquality :=
    complete.structConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    leftFields.orderedArguments_unique exprUnique left.determined rightFields
      left.nominal.arguments right.nominal.arguments
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal typeArgumentsEquality constArgumentsEquality
  have fieldsEquality := leftFields.unique_of_expr exprUnique rightFields
  exact ⟨rfl, typeArgumentsEquality, constArgumentsEquality,
    artifactEquality, fieldsEquality⟩

/-- Explicit struct arguments are fixed by their source syntax; complete
    field provenance then makes checking functional across the two finite
    substitution witnesses. -/
theorem StructExplicitEvidence.results_unique_of_fields
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : StructExplicitEvidence outer concrete symbolic path leftConstructor
      leftInner leftTypeArguments leftConstArguments leftResolved)
    (right : StructExplicitEvidence outer concrete symbolic path rightConstructor
      rightInner rightTypeArguments rightConstArguments rightResolved)
    (leftFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      leftConstructor.fields surfaceFields leftCoreFields)
    (rightFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      rightConstructor.fields surfaceFields rightCoreFields) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧ leftCoreFields = rightCoreFields := by
  have constructorEquality :=
    complete.structConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    left.explicitArguments.orderedArguments_unique complete.metadataUnique
      right.explicitArguments left.nominal.arguments right.nominal.arguments
  cases typeArgumentsEquality
  cases constArgumentsEquality
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal rfl rfl
  have fieldsEquality :=
    leftFields.unique_of_expr_and_arguments complete checkUnique
      left.selected.member (fun _ member => member) left.nominal.arguments
      right.nominal.arguments rightFields
  exact ⟨rfl, rfl, rfl,
    artifactEquality, fieldsEquality⟩

/-- A nongeneric struct has empty ordered arguments by construction, but its
    two substitution witnesses may still differ outside the empty domain. -/
theorem StructNongenericEvidence.results_unique_of_fields
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : StructNongenericEvidence outer concrete symbolic path leftConstructor
      leftInner leftResolved)
    (right : StructNongenericEvidence outer concrete symbolic path rightConstructor
      rightInner rightResolved)
    (leftFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      leftConstructor.fields surfaceFields leftCoreFields)
    (rightFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      rightConstructor.fields surfaceFields rightCoreFields) :
    leftConstructor = rightConstructor ∧ leftResolved = rightResolved ∧
      leftCoreFields = rightCoreFields := by
  have constructorEquality :=
    complete.structConstructor_unique left.selected right.selected
  cases constructorEquality
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal rfl rfl
  have fieldsEquality :=
    leftFields.unique_of_expr_and_arguments complete checkUnique
      left.selected.member (fun _ member => member) left.nominal.arguments
      right.nominal.arguments rightFields
  exact ⟨rfl, artifactEquality, fieldsEquality⟩

/-- All three struct-construction modes are mutually disjoint and internally
    functional. Explicit syntax cannot also be implicit, while inferred and
    nongeneric modes disagree on whether the selected constructor has generic
    parameters. -/
theorem ExprInferenceDerivationSpecializes.structValue_unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.structValue path surfaceFields)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.structValue path surfaceFields)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | structExplicit leftEvidence leftFields =>
      cases right with
      | structExplicit rightEvidence rightFields =>
          rcases leftEvidence.results_unique_of_fields complete
              (fun _member => checkUnique)
              rightEvidence leftFields rightFields with
            ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | structInferred rightEvidence rightFields =>
          exact (leftEvidence.explicitArguments.excludesNoGenericArguments
            rightEvidence.implicitArguments).elim
      | structNongeneric rightEvidence rightFields =>
          exact (leftEvidence.explicitArguments.excludesNoGenericArguments
            rightEvidence.implicitArguments).elim
  | structInferred leftEvidence leftFields =>
      cases right with
      | structExplicit rightEvidence rightFields =>
          exact (rightEvidence.explicitArguments.excludesNoGenericArguments
            leftEvidence.implicitArguments).elim
      | structInferred rightEvidence rightFields =>
          rcases leftEvidence.results_unique_of_fields complete
              (fun _member => inferUnique)
              rightEvidence leftFields rightFields with
            ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | structNongeneric rightEvidence rightFields =>
          have constructorEquality := complete.structConstructor_unique
            leftEvidence.selected rightEvidence.selected
          cases constructorEquality
          exact (leftEvidence.generic rightEvidence.nongeneric).elim
  | structNongeneric leftEvidence leftFields =>
      cases right with
      | structExplicit rightEvidence rightFields =>
          exact (rightEvidence.explicitArguments.excludesNoGenericArguments
            leftEvidence.implicitArguments).elim
      | structInferred rightEvidence rightFields =>
          have constructorEquality := complete.structConstructor_unique
            leftEvidence.selected rightEvidence.selected
          cases constructorEquality
          exact (rightEvidence.generic leftEvidence.nongeneric).elim
      | structNongeneric rightEvidence rightFields =>
          rcases leftEvidence.results_unique_of_fields complete
              (fun _member => checkUnique)
              rightEvidence leftFields rightFields with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

/-- Payload-driven enum construction has the same functionality property. The
    recursive payload derivation first fixes the observed types; occurrence
    coverage then fixes the generic arguments and therefore the artifact. -/
theorem VariantInferenceEvidence.results_unique_of_payload
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (exprUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : VariantInferenceEvidence outer concrete symbolic path leftConstructor
      leftInner leftObservedTypes leftTypeArguments leftConstArguments
      leftResolved)
    (right : VariantInferenceEvidence outer concrete symbolic path rightConstructor
      rightInner rightObservedTypes rightTypeArguments rightConstArguments
      rightResolved)
    (leftPayload : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftObservedTypes leftGroundPayload leftCoreArguments)
    (rightPayload : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightObservedTypes rightGroundPayload rightCoreArguments) :
    leftConstructor = rightConstructor ∧
      leftObservedTypes = rightObservedTypes ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧
      leftGroundPayload = rightGroundPayload ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality :=
    complete.symbolicVariantConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨observedTypesEquality, groundPayloadEquality, coreArgumentsEquality⟩ :=
    ExprListInferenceDerivationSpecializes.unique_of_expr exprUnique
      leftPayload rightPayload
  have typeMatchesRight : Static.TypesSymbolicallyMatch rightInner
      leftConstructor.payload leftObservedTypes := by
    rw [observedTypesEquality]
    exact right.typeMatches
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined left.typeMatches typeMatchesRight
      left.nominal.arguments right.nominal.arguments
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal typeArgumentsEquality constArgumentsEquality
  exact ⟨rfl, observedTypesEquality, typeArgumentsEquality,
    constArgumentsEquality, artifactEquality, groundPayloadEquality,
    coreArgumentsEquality⟩

theorem VariantExplicitEvidence.results_unique_of_payload
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : VariantExplicitEvidence outer concrete symbolic path leftConstructor
      leftInner leftTypeArguments leftConstArguments leftResolved)
    (right : VariantExplicitEvidence outer concrete symbolic path rightConstructor
      rightInner rightTypeArguments rightConstArguments rightResolved)
    (leftPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner surfaceArguments
      leftConstructor.payload leftCoreArguments)
    (rightPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner surfaceArguments
      rightConstructor.payload rightCoreArguments) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality :=
    complete.symbolicVariantConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    left.explicitArguments.orderedArguments_unique complete.metadataUnique
      right.explicitArguments left.nominal.arguments right.nominal.arguments
  cases typeArgumentsEquality
  cases constArgumentsEquality
  obtain ⟨leftExpectedTypes, leftSubstituted⟩ := leftPayload.substitutedTypes
  obtain ⟨rightExpectedTypes, rightSubstituted⟩ :=
    rightPayload.substitutedTypes
  have expectedTypesEquality := complete.variantPayloadSubstitute_unique
    left.selected.2.member left.nominal.arguments right.nominal.arguments
    leftSubstituted rightSubstituted
  have substitutionsAgree : Static.substituteTypes leftInner
      leftConstructor.payload =
      Static.substituteTypes rightInner leftConstructor.payload := by
    rw [leftSubstituted, rightSubstituted, expectedTypesEquality]
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal rfl rfl
  have payloadEquality :=
    leftPayload.unique_of_expr_and_substitution checkUnique rightPayload
      substitutionsAgree
  exact ⟨rfl, rfl, rfl, artifactEquality, payloadEquality⟩

theorem VariantNongenericEvidence.results_unique_of_payload
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : VariantNongenericEvidence outer concrete symbolic path leftConstructor
      leftInner leftResolved)
    (right : VariantNongenericEvidence outer concrete symbolic path rightConstructor
      rightInner rightResolved)
    (leftPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner surfaceArguments
      leftConstructor.payload leftCoreArguments)
    (rightPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner surfaceArguments
      rightConstructor.payload rightCoreArguments) :
    leftConstructor = rightConstructor ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality :=
    complete.symbolicVariantConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨leftExpectedTypes, leftSubstituted⟩ := leftPayload.substitutedTypes
  obtain ⟨rightExpectedTypes, rightSubstituted⟩ :=
    rightPayload.substitutedTypes
  have expectedTypesEquality := complete.variantPayloadSubstitute_unique
    left.selected.2.member left.nominal.arguments right.nominal.arguments
    leftSubstituted rightSubstituted
  have substitutionsAgree : Static.substituteTypes leftInner
      leftConstructor.payload =
      Static.substituteTypes rightInner leftConstructor.payload := by
    rw [leftSubstituted, rightSubstituted, expectedTypesEquality]
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal rfl rfl
  have payloadEquality :=
    leftPayload.unique_of_expr_and_substitution checkUnique rightPayload
      substitutionsAgree
  exact ⟨rfl, artifactEquality, payloadEquality⟩

theorem VariantExplicitEvidence.excludesInference
    (explicit : VariantExplicitEvidence outer concrete symbolic path
      explicitConstructor explicitInner explicitTypes explicitConstants
      explicitResolved)
    (inferred : VariantInferenceEvidence outer concrete symbolic path
      inferredConstructor inferredInner observedTypes inferredTypes
      inferredConstants inferredResolved) : False :=
  explicit.explicitArguments.excludesNoGenericArguments
    inferred.implicitArguments

theorem VariantExplicitEvidence.excludesNongeneric
    (explicit : VariantExplicitEvidence outer concrete symbolic path
      explicitConstructor explicitInner explicitTypes explicitConstants
      explicitResolved)
    (nongeneric : VariantNongenericEvidence outer concrete symbolic path
      nongenericConstructor nongenericInner nongenericResolved) : False :=
  explicit.explicitArguments.excludesNoGenericArguments
    nongeneric.implicitArguments

theorem VariantInferenceEvidence.excludesNongeneric
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferred : VariantInferenceEvidence outer concrete symbolic path
      inferredConstructor inferredInner observedTypes inferredTypes
      inferredConstants inferredResolved)
    (nongeneric : VariantNongenericEvidence outer concrete symbolic path
      nongenericConstructor nongenericInner nongenericResolved) : False := by
  have constructorEquality := complete.symbolicVariantConstructor_unique
    inferred.selected nongeneric.selected
  cases constructorEquality
  exact inferred.generic nongeneric.nongeneric

/-- Two applications of the contextual struct rule to the same expected type
    select the same constructor arguments, artifact, and emitted fields. -/
theorem contextualStructResults_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (leftSelected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path leftConstructor)
    (rightSelected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path rightConstructor)
    (leftExpected : expectedType = Static.Ty.nominal leftConstructor.sourceType
      leftTypeArguments leftConstArguments)
    (rightExpected : expectedType = Static.Ty.nominal rightConstructor.sourceType
      rightTypeArguments rightConstArguments)
    (leftArguments : Static.SymbolicArgumentsBound leftInner
      leftConstructor.genericParameters leftTypeArguments leftConstArguments)
    (rightArguments : Static.SymbolicArgumentsBound rightInner
      rightConstructor.genericParameters rightTypeArguments rightConstArguments)
    (leftTypeArgumentsGround : Static.instantiateTypes outer leftTypeArguments =
      some leftGroundTypeArguments)
    (rightTypeArgumentsGround : Static.instantiateTypes outer rightTypeArguments =
      some rightGroundTypeArguments)
    (leftConstArgumentsGround : Static.instantiateConstants outer
      leftConstArguments = some leftGroundConstArguments)
    (rightConstArgumentsGround : Static.instantiateConstants outer
      rightConstArguments = some rightGroundConstArguments)
    (leftArtifact : NominalArtifactDemand concrete leftConstructor.declaration
      leftConstructor.sourceType .structure leftGroundTypeArguments
      leftGroundConstArguments leftResolved)
    (rightArtifact : NominalArtifactDemand concrete rightConstructor.declaration
      rightConstructor.sourceType .structure rightGroundTypeArguments
      rightGroundConstArguments rightResolved)
    (leftFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      leftConstructor.fields surfaceFields leftCoreFields)
    (rightFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      rightConstructor.fields surfaceFields rightCoreFields) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧ leftCoreFields = rightCoreFields := by
  have constructorEquality := complete.structConstructor_unique
    leftSelected rightSelected
  cases constructorEquality
  have expectedEquality := leftExpected.symm.trans rightExpected
  injection expectedEquality with sourceTypeEquality typeArgumentsEquality
    constArgumentsEquality
  cases sourceTypeEquality
  cases typeArgumentsEquality
  cases constArgumentsEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (leftTypeArgumentsGround.symm.trans rightTypeArgumentsGround)
  have groundConstArgumentsEquality := Option.some.inj
    (leftConstArgumentsGround.symm.trans rightConstArgumentsGround)
  have artifactEquality := complete.concreteNominalArtifact_unique contexts
    leftArtifact rightArtifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  have fieldsEquality :=
    leftFields.unique_of_expr_and_arguments complete checkUnique
      leftSelected.member (fun _ member => member) leftArguments rightArguments
      rightFields
  exact ⟨rfl, rfl, rfl, artifactEquality, fieldsEquality⟩

/-- The contextual variant rule obeys the same expected-type identity key. -/
theorem contextualVariantResults_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (leftSelected : SelectsSymbolicVariantConstructor symbolic path leftConstructor)
    (rightSelected : SelectsSymbolicVariantConstructor symbolic path rightConstructor)
    (leftExpected : expectedType = Static.Ty.nominal leftConstructor.sourceType
      leftTypeArguments leftConstArguments)
    (rightExpected : expectedType = Static.Ty.nominal rightConstructor.sourceType
      rightTypeArguments rightConstArguments)
    (leftArguments : Static.SymbolicArgumentsBound leftInner
      leftConstructor.genericParameters leftTypeArguments leftConstArguments)
    (rightArguments : Static.SymbolicArgumentsBound rightInner
      rightConstructor.genericParameters rightTypeArguments rightConstArguments)
    (leftTypeArgumentsGround : Static.instantiateTypes outer leftTypeArguments =
      some leftGroundTypeArguments)
    (rightTypeArgumentsGround : Static.instantiateTypes outer rightTypeArguments =
      some rightGroundTypeArguments)
    (leftConstArgumentsGround : Static.instantiateConstants outer
      leftConstArguments = some leftGroundConstArguments)
    (rightConstArgumentsGround : Static.instantiateConstants outer
      rightConstArguments = some rightGroundConstArguments)
    (leftArtifact : NominalArtifactDemand concrete
      leftConstructor.nominalDeclaration leftConstructor.sourceType .enumeration
      leftGroundTypeArguments leftGroundConstArguments leftResolved)
    (rightArtifact : NominalArtifactDemand concrete
      rightConstructor.nominalDeclaration rightConstructor.sourceType .enumeration
      rightGroundTypeArguments rightGroundConstArguments rightResolved)
    (leftPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner surfaceArguments
      leftConstructor.payload leftCoreArguments)
    (rightPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner surfaceArguments
      rightConstructor.payload rightCoreArguments) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality := complete.symbolicVariantConstructor_unique
    leftSelected rightSelected
  cases constructorEquality
  have expectedEquality := leftExpected.symm.trans rightExpected
  injection expectedEquality with sourceTypeEquality typeArgumentsEquality
    constArgumentsEquality
  cases sourceTypeEquality
  cases typeArgumentsEquality
  cases constArgumentsEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (leftTypeArgumentsGround.symm.trans rightTypeArgumentsGround)
  have groundConstArgumentsEquality := Option.some.inj
    (leftConstArgumentsGround.symm.trans rightConstArgumentsGround)
  have artifactEquality := complete.concreteNominalArtifact_unique contexts
    leftArtifact rightArtifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  obtain ⟨leftExpectedTypes, leftSubstituted⟩ := leftPayload.substitutedTypes
  obtain ⟨rightExpectedTypes, rightSubstituted⟩ :=
    rightPayload.substitutedTypes
  have expectedTypesEquality := complete.variantPayloadSubstitute_unique
    leftSelected.2.member leftArguments rightArguments leftSubstituted
    rightSubstituted
  have substitutionsAgree : Static.substituteTypes leftInner
      leftConstructor.payload =
      Static.substituteTypes rightInner leftConstructor.payload := by
    rw [leftSubstituted, rightSubstituted, expectedTypesEquality]
  have payloadEquality :=
    leftPayload.unique_of_expr_and_substitution checkUnique rightPayload
      substitutionsAgree
  exact ⟨rfl, rfl, rfl, artifactEquality, payloadEquality⟩

/-- Inferred direct calls are functional once inference of their argument list
    is functional. Source selection fixes the scheme, occurrence coverage
    fixes its ordered generic arguments, declaration provenance fixes the
    instantiated signature, and the complete artifact table fixes the emitted
    function row. -/
theorem DirectCallInferenceEvidence.results_unique_of_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : DirectCallInferenceEvidence outer concrete symbolic path
      leftObservedTypes leftReturnType leftScheme leftInner leftResolved)
    (right : DirectCallInferenceEvidence outer concrete symbolic path
      rightObservedTypes rightReturnType rightScheme rightInner rightResolved)
    (leftArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftObservedTypes leftResolved.parameterTypes leftCoreArguments)
    (rightArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightObservedTypes rightResolved.parameterTypes rightCoreArguments) :
    leftScheme = rightScheme ∧ leftObservedTypes = rightObservedTypes ∧
      leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have schemeEquality := left.selected.unique right.selected
  cases schemeEquality
  obtain ⟨observedTypesEquality, _parameterGroundsEquality,
      coreArgumentsEquality⟩ :=
    ExprListInferenceDerivationSpecializes.unique_of_expr inferUnique
      leftArguments rightArguments
  cases observedTypesEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined left.argumentMatches right.argumentMatches
      left.genericArguments right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨_parameterTypesEquality, returnTypeEquality⟩ :=
    complete.functionSignatureSubstitute_unique left.selected.member
      left.genericArguments rightGenericArguments
      left.argumentMatches.substitutes right.argumentMatches.substitutes
      left.returnSubstitute right.returnSubstitute
  cases returnTypeEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have artifactEquality := complete.concreteFunctionArtifact_unique contexts
    left.artifact right.artifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  cases artifactEquality
  exact ⟨rfl, rfl, rfl, rfl, coreArgumentsEquality⟩

/-- Explicit direct calls observe the source generic argument list exactly, so
    retained-argument functionality replaces occurrence-based inference. -/
theorem DirectCallExplicitEvidence.results_unique_of_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : DirectCallExplicitEvidence outer concrete symbolic path
      leftParameterTypes leftReturnType leftScheme leftInner leftResolved)
    (right : DirectCallExplicitEvidence outer concrete symbolic path
      rightParameterTypes rightReturnType rightScheme rightInner rightResolved)
    (leftArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftParameterTypes leftResolved.parameterTypes leftCoreArguments)
    (rightArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightParameterTypes rightResolved.parameterTypes rightCoreArguments) :
    leftScheme = rightScheme ∧ leftParameterTypes = rightParameterTypes ∧
      leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have schemeEquality := left.selected.unique right.selected
  cases schemeEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    left.explicitArguments.orderedArguments_unique complete.metadataUnique
      right.explicitArguments left.genericArguments right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨parameterTypesEquality, returnTypeEquality⟩ :=
    complete.functionSignatureSubstitute_unique left.selected.member
      left.genericArguments rightGenericArguments left.parametersSubstitute
      right.parametersSubstitute left.returnSubstitute right.returnSubstitute
  cases parameterTypesEquality
  cases returnTypeEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have artifactEquality := complete.concreteFunctionArtifact_unique contexts
    left.artifact right.artifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  cases artifactEquality
  obtain ⟨_parameterGroundsEquality, coreArgumentsEquality⟩ :=
    ExprListCheckingDerivationSpecializes.unique_of_expr checkUnique
      leftArguments rightArguments
  exact ⟨rfl, rfl, rfl, rfl, coreArgumentsEquality⟩

/-- Nongeneric direct calls have the empty specialization key, leaving only
    source-scheme selection, complete artifact identity, and recursive
    argument checking to determine their result. -/
theorem DirectCallNongenericEvidence.results_unique_of_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : DirectCallNongenericEvidence outer concrete symbolic path
      leftScheme leftResolved)
    (right : DirectCallNongenericEvidence outer concrete symbolic path
      rightScheme rightResolved)
    (leftArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftScheme.parameterTypes leftResolved.parameterTypes leftCoreArguments)
    (rightArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightScheme.parameterTypes rightResolved.parameterTypes rightCoreArguments) :
    leftScheme = rightScheme ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have schemeEquality := left.selected.unique right.selected
  cases schemeEquality
  have artifactEquality := complete.concreteFunctionArtifact_unique contexts
    left.artifact right.artifact rfl rfl
  cases artifactEquality
  obtain ⟨_parameterGroundsEquality, coreArgumentsEquality⟩ :=
    ExprListCheckingDerivationSpecializes.unique_of_expr checkUnique
      leftArguments rightArguments
  exact ⟨rfl, rfl, coreArgumentsEquality⟩

theorem DirectCallExplicitEvidence.excludesInference
    (explicit : DirectCallExplicitEvidence outer concrete symbolic path
      explicitParameterTypes explicitReturnType explicitScheme explicitInner
      explicitResolved)
    (inferred : DirectCallInferenceEvidence outer concrete symbolic path
      inferredObservedTypes inferredReturnType inferredScheme inferredInner
      inferredResolved) : False :=
  explicit.explicitArguments.excludesNoGenericArguments
    inferred.implicitArguments

theorem DirectCallExplicitEvidence.excludesNongeneric
    (explicit : DirectCallExplicitEvidence outer concrete symbolic path
      explicitParameterTypes explicitReturnType explicitScheme explicitInner
      explicitResolved)
    (nongeneric : DirectCallNongenericEvidence outer concrete symbolic path
      nongenericScheme nongenericResolved) : False :=
  explicit.explicitArguments.excludesNoGenericArguments
    nongeneric.implicitArguments

theorem DirectCallInferenceEvidence.excludesNongeneric
    (inferred : DirectCallInferenceEvidence outer concrete symbolic path
      inferredObservedTypes inferredReturnType inferredScheme inferredInner
      inferredResolved)
    (nongeneric : DirectCallNongenericEvidence outer concrete symbolic path
      nongenericScheme nongenericResolved) : False := by
  have schemeEquality := inferred.selected.unique nongeneric.selected
  cases schemeEquality
  exact inferred.generic nongeneric.nongeneric

/-- Substitution of the source-visible parameter vector of an associated
    function is functional once declaration provenance has fixed substitution
    of the retained receiver and ordinary parameter vector.  The proof covers
    both receiverless functions and explicit typed receivers; `self` and
    `&self` cannot occur in associated-call syntax. -/
theorem associatedArgumentSubstitute_unique
    {scheme : Static.MethodScheme}
    {leftSubstitution rightSubstitution : Static.SymbolicSubstitution}
    {leftSourceParameterTypes rightSourceParameterTypes : List Static.Ty}
    {leftReceiverType rightReceiverType : Static.Ty}
    {leftStoredArgumentTypes rightStoredArgumentTypes : List Static.Ty}
    {leftAssociatedArgumentTypes rightAssociatedArgumentTypes : List Static.Ty}
    (leftParameters : scheme.associatedArgumentTypes? =
      some leftSourceParameterTypes)
    (rightParameters : scheme.associatedArgumentTypes? =
      some rightSourceParameterTypes)
    (leftReceiver : scheme.receiverType.substitute leftSubstitution =
      some leftReceiverType)
    (rightReceiver : scheme.receiverType.substitute rightSubstitution =
      some rightReceiverType)
    (leftStored : Static.substituteTypes leftSubstitution scheme.argumentTypes =
      some leftStoredArgumentTypes)
    (rightStored : Static.substituteTypes rightSubstitution scheme.argumentTypes =
      some rightStoredArgumentTypes)
    (leftAssociated : Static.substituteTypes leftSubstitution
      leftSourceParameterTypes = some leftAssociatedArgumentTypes)
    (rightAssociated : Static.substituteTypes rightSubstitution
      rightSourceParameterTypes = some rightAssociatedArgumentTypes)
    (receiverEquality : leftReceiverType = rightReceiverType)
    (storedEquality : leftStoredArgumentTypes = rightStoredArgumentTypes) :
    leftAssociatedArgumentTypes = rightAssociatedArgumentTypes := by
  cases receiverEquality
  cases storedEquality
  have sourceParametersEquality := Option.some.inj
    (leftParameters.symm.trans rightParameters)
  cases sourceParametersEquality
  cases mode : scheme.receiverMode with
  | none =>
      have sourceShape : scheme.argumentTypes = leftSourceParameterTypes := by
        simpa [Static.MethodScheme.associatedArgumentTypes?, mode] using
          leftParameters
      cases sourceShape
      have leftResult : leftStoredArgumentTypes =
          leftAssociatedArgumentTypes :=
        Option.some.inj (leftStored.symm.trans leftAssociated)
      have rightResult : leftStoredArgumentTypes =
          rightAssociatedArgumentTypes :=
        Option.some.inj (rightStored.symm.trans rightAssociated)
      exact leftResult.symm.trans rightResult
  | explicit =>
      have sourceShape : scheme.receiverType :: scheme.argumentTypes =
          leftSourceParameterTypes := by
        simpa [Static.MethodScheme.associatedArgumentTypes?, mode] using
          leftParameters
      cases sourceShape
      have leftResult : leftReceiverType :: leftStoredArgumentTypes =
          leftAssociatedArgumentTypes := by
        simpa [Static.substituteTypes, leftReceiver, leftStored] using
          leftAssociated
      have rightResult : leftReceiverType :: leftStoredArgumentTypes =
          rightAssociatedArgumentTypes := by
        simpa [Static.substituteTypes, rightReceiver, rightStored] using
          rightAssociated
      exact leftResult.symm.trans rightResult
  | value =>
      simp [Static.MethodScheme.associatedArgumentTypes?, mode] at leftParameters
  | reference =>
      simp [Static.MethodScheme.associatedArgumentTypes?, mode] at leftParameters

/-- Two inferred associated-call occurrences select one symbolic result, one
    monomorphic method artifact, and one emitted argument vector. -/
theorem AssociatedCallInferenceEvidence.results_unique_of_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (argumentsUnique : ∀ {leftSymbolic leftGround leftCore rightSymbolic
        rightGround rightCore},
      ExprListInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments leftSymbolic leftGround leftCore →
        ExprListInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : AssociatedCallInferenceEvidence outer concrete symbolic path
      leftOwnerPath leftName leftReceiverType leftSourceParameterTypes
      leftObservedTypes leftGroundArgumentTypes leftReturnType leftScheme
      leftInner leftResolved)
    (right : AssociatedCallInferenceEvidence outer concrete symbolic path
      rightOwnerPath rightName rightReceiverType rightSourceParameterTypes
      rightObservedTypes rightGroundArgumentTypes rightReturnType rightScheme
      rightInner rightResolved)
    (leftArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftObservedTypes leftGroundArgumentTypes leftCoreArguments)
    (rightArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightObservedTypes rightGroundArgumentTypes rightCoreArguments) :
    leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have splitEquality := Option.some.inj (left.split.symm.trans right.split)
  injection splitEquality with ownerPathEquality nameEquality
  cases ownerPathEquality
  cases nameEquality
  have receiverTypeEquality := TypeRetains.unique complete.metadataUnique
    left.owner right.owner
  cases receiverTypeEquality
  obtain ⟨observedTypesEquality, groundArgumentTypesEquality,
      coreArgumentsEquality⟩ := argumentsUnique leftArguments rightArguments
  cases observedTypesEquality
  cases groundArgumentTypesEquality
  have declarationEquality := left.unique rightScheme right.schemeMember
    ⟨rightInner, right.schemeName, right.receiverMatch,
      right.genericArguments.parametersBound, right.requirements.symbolic⟩
    right.symbolicPreferred
  have schemeEquality := complete.metadataUnique.methods leftScheme
    left.schemeMember rightScheme right.schemeMember declarationEquality.symm
  cases schemeEquality
  have sourceParameterTypesEquality := Option.some.inj
    (left.associatedParameters.symm.trans right.associatedParameters)
  cases sourceParameterTypesEquality
  have orderedArgumentsEquality :
      left.symbolicTypeArguments = right.symbolicTypeArguments ∧
        left.symbolicConstArguments = right.symbolicConstArguments := by
    cases mode : leftScheme.receiverMode with
    | none =>
        have sourceShape : leftScheme.argumentTypes =
            leftSourceParameterTypes := by
          simpa [Static.MethodScheme.associatedArgumentTypes?, mode] using
            left.associatedParameters
        cases sourceShape
        exact
          SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
            left.determined (.cons left.receiverMatch left.argumentMatches)
            (.cons right.receiverMatch right.argumentMatches)
            left.genericArguments right.genericArguments
    | explicit =>
        have sourceShape : leftScheme.receiverType :: leftScheme.argumentTypes =
            leftSourceParameterTypes := by
          simpa [Static.MethodScheme.associatedArgumentTypes?, mode] using
            left.associatedParameters
        cases sourceShape
        exact
          SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
            left.determined left.argumentMatches right.argumentMatches
            left.genericArguments right.genericArguments
    | value =>
        have impossible := left.associatedParameters
        simp [Static.MethodScheme.associatedArgumentTypes?, mode] at impossible
    | reference =>
        have impossible := left.associatedParameters
        simp [Static.MethodScheme.associatedArgumentTypes?, mode] at impossible
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    orderedArgumentsEquality
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨_receiverTypeEquality, _storedArgumentTypesEquality,
      returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique left.schemeMember
      left.genericArguments rightGenericArguments
      left.receiverMatch.substitutes right.receiverMatch.substitutes
      left.storedArgumentsSubstitute right.storedArgumentsSubstitute
      left.returnSubstitute right.returnSubstitute
  cases returnTypeEquality
  have resolvedReceiverEquality : leftResolved.receiverType =
      rightResolved.receiverType :=
    Option.some.inj (left.ownerGrounds.symm.trans right.ownerGrounds)
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have resolvedEquality := complete.concreteMethodArtifact_unique contexts
    resolvedReceiverEquality left.artifact right.artifact
    groundTypeArgumentsEquality groundConstArgumentsEquality
  cases resolvedEquality
  exact ⟨rfl, rfl, coreArgumentsEquality⟩

/-- Two contextual associated-call occurrences agree after the owner type fixes
    the declaration and its complete source-visible parameter signature. -/
theorem AssociatedCallContextualEvidence.results_unique_of_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (argumentsUnique : ∀ {expectedTypes leftGround leftCore rightGround
        rightCore},
      ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes leftGround leftCore →
        ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : AssociatedCallContextualEvidence outer concrete symbolic path
      leftOwnerPath leftName leftReceiverType leftSourceParameterTypes
      leftExpectedArgumentTypes leftGroundArgumentTypes leftReturnType leftScheme
      leftInner leftResolved)
    (right : AssociatedCallContextualEvidence outer concrete symbolic path
      rightOwnerPath rightName rightReceiverType rightSourceParameterTypes
      rightExpectedArgumentTypes rightGroundArgumentTypes rightReturnType rightScheme
      rightInner rightResolved)
    (leftArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftExpectedArgumentTypes leftGroundArgumentTypes leftCoreArguments)
    (rightArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightExpectedArgumentTypes rightGroundArgumentTypes rightCoreArguments) :
    leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have splitEquality := Option.some.inj (left.split.symm.trans right.split)
  injection splitEquality with ownerPathEquality nameEquality
  cases ownerPathEquality
  cases nameEquality
  have receiverTypeEquality := TypeRetains.unique complete.metadataUnique
    left.owner right.owner
  cases receiverTypeEquality
  have declarationEquality := left.unique rightScheme right.schemeMember
    ⟨rightInner, right.schemeName, right.receiverMatch,
      right.genericArguments.parametersBound, right.requirements.symbolic⟩
    right.symbolicPreferred
  have schemeEquality := complete.metadataUnique.methods leftScheme
    left.schemeMember rightScheme right.schemeMember declarationEquality.symm
  cases schemeEquality
  have sourceParameterTypesEquality := Option.some.inj
    (left.associatedParameters.symm.trans right.associatedParameters)
  cases sourceParameterTypesEquality
  have leftMatches : Static.TypesSymbolicallyMatch leftInner
      [leftScheme.receiverType] [leftReceiverType] :=
    .cons left.receiverMatch .nil
  have rightMatches : Static.TypesSymbolicallyMatch rightInner
      [leftScheme.receiverType] [leftReceiverType] :=
    .cons right.receiverMatch .nil
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined leftMatches rightMatches left.genericArguments
      right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨receiverSubstituteEquality, storedArgumentsEquality,
      returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique left.schemeMember
      left.genericArguments rightGenericArguments
      left.receiverMatch.substitutes right.receiverMatch.substitutes
      left.storedArgumentsSubstitute right.storedArgumentsSubstitute
      left.returnSubstitute right.returnSubstitute
  have expectedArgumentTypesEquality := associatedArgumentSubstitute_unique
    left.associatedParameters right.associatedParameters
    left.receiverMatch.substitutes right.receiverMatch.substitutes
    left.storedArgumentsSubstitute right.storedArgumentsSubstitute
    left.argumentsSubstitute right.argumentsSubstitute
    receiverSubstituteEquality storedArgumentsEquality
  cases expectedArgumentTypesEquality
  cases returnTypeEquality
  obtain ⟨groundArgumentTypesEquality, coreArgumentsEquality⟩ :=
    argumentsUnique leftArguments rightArguments
  cases groundArgumentTypesEquality
  have resolvedReceiverEquality : leftResolved.receiverType =
      rightResolved.receiverType :=
    Option.some.inj (left.ownerGrounds.symm.trans right.ownerGrounds)
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have resolvedEquality := complete.concreteMethodArtifact_unique contexts
    resolvedReceiverEquality left.artifact right.artifact
    groundTypeArgumentsEquality groundConstArgumentsEquality
  cases resolvedEquality
  exact ⟨rfl, rfl, coreArgumentsEquality⟩

/-- If both associated-call rules apply, receiver-only determination in the
    contextual rule fixes the inferred rule's generic arguments as well. -/
theorem AssociatedCallInferenceEvidence.results_unique_of_contextual
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (argumentsUnique : ∀ {expectedTypes leftGround leftCore rightGround
        rightCore},
      ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes leftGround leftCore →
        ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (inferred : AssociatedCallInferenceEvidence outer concrete symbolic path
      inferredOwnerPath inferredName inferredReceiverType
      inferredSourceParameterTypes observedTypes inferredGroundArgumentTypes
      inferredReturnType inferredScheme inferredInner inferredResolved)
    (contextual : AssociatedCallContextualEvidence outer concrete symbolic path
      contextualOwnerPath contextualName contextualReceiverType
      contextualSourceParameterTypes expectedTypes contextualGroundArgumentTypes
      contextualReturnType contextualScheme contextualInner contextualResolved)
    (inferredArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      observedTypes inferredGroundArgumentTypes inferredCoreArguments)
    (contextualArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      expectedTypes contextualGroundArgumentTypes contextualCoreArguments) :
    inferredReturnType = contextualReturnType ∧
      inferredResolved = contextualResolved ∧
      inferredCoreArguments = contextualCoreArguments := by
  have splitEquality := Option.some.inj
    (inferred.split.symm.trans contextual.split)
  injection splitEquality with ownerPathEquality nameEquality
  cases ownerPathEquality
  cases nameEquality
  have receiverTypeEquality := TypeRetains.unique complete.metadataUnique
    inferred.owner contextual.owner
  cases receiverTypeEquality
  have declarationEquality := contextual.unique inferredScheme
    inferred.schemeMember
    ⟨inferredInner, inferred.schemeName, inferred.receiverMatch,
      inferred.genericArguments.parametersBound, inferred.requirements.symbolic⟩
    inferred.symbolicPreferred
  have schemeEquality := complete.metadataUnique.methods inferredScheme
    inferred.schemeMember contextualScheme contextual.schemeMember
    declarationEquality
  cases schemeEquality
  have sourceParameterTypesEquality := Option.some.inj
    (inferred.associatedParameters.symm.trans contextual.associatedParameters)
  cases sourceParameterTypesEquality
  have inferredMatches : Static.TypesSymbolicallyMatch inferredInner
      [inferredScheme.receiverType] [inferredReceiverType] :=
    .cons inferred.receiverMatch .nil
  have contextualMatches : Static.TypesSymbolicallyMatch contextualInner
      [inferredScheme.receiverType] [inferredReceiverType] :=
    .cons contextual.receiverMatch .nil
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      contextual.determined inferredMatches contextualMatches
      inferred.genericArguments contextual.genericArguments
  have contextualGenericArguments : Static.SymbolicArgumentsBound contextualInner
      inferredScheme.genericParameters inferred.symbolicTypeArguments
      inferred.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact contextual.genericArguments
  obtain ⟨receiverSubstituteEquality, storedArgumentsEquality,
      returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique inferred.schemeMember
      inferred.genericArguments contextualGenericArguments
      inferred.receiverMatch.substitutes contextual.receiverMatch.substitutes
      inferred.storedArgumentsSubstitute contextual.storedArgumentsSubstitute
      inferred.returnSubstitute contextual.returnSubstitute
  have argumentTypesEquality := associatedArgumentSubstitute_unique
    inferred.associatedParameters contextual.associatedParameters
    inferred.receiverMatch.substitutes contextual.receiverMatch.substitutes
    inferred.storedArgumentsSubstitute contextual.storedArgumentsSubstitute
    inferred.argumentMatches.substitutes contextual.argumentsSubstitute
    receiverSubstituteEquality storedArgumentsEquality
  cases argumentTypesEquality
  cases returnTypeEquality
  obtain ⟨groundArgumentTypesEquality, coreArgumentsEquality⟩ :=
    argumentsUnique inferredArguments.asChecking contextualArguments
  cases groundArgumentTypesEquality
  have resolvedReceiverEquality : inferredResolved.receiverType =
      contextualResolved.receiverType :=
    Option.some.inj (inferred.ownerGrounds.symm.trans contextual.ownerGrounds)
  have groundTypeArgumentsEquality := Option.some.inj
    (inferred.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        contextual.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (inferred.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans contextual.constArgumentsGround))
  have resolvedEquality := complete.concreteMethodArtifact_unique contexts
    resolvedReceiverEquality inferred.artifact contextual.artifact
    groundTypeArgumentsEquality groundConstArgumentsEquality
  cases resolvedEquality
  exact ⟨rfl, rfl, coreArgumentsEquality⟩

/-- Inferred method calls are functional once their receiver and argument
    expressions are. Ground receiver/name lookup coherence fixes the selected
    scheme; receiver/argument occurrence coverage then fixes its symbolic
    generic arguments and declaration provenance fixes the return type. -/
theorem MethodCallInferenceEvidence.results_unique_of_children
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (receiverUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (argumentsUnique : ∀ {leftSymbolic leftGround leftCore rightSymbolic
        rightGround rightCore},
      ExprListInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments leftSymbolic leftGround leftCore →
        ExprListInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : MethodCallInferenceEvidence outer concrete symbolic
      leftReceiverType name leftObservedTypes leftReturnType leftScheme
      leftInner leftResolved)
    (right : MethodCallInferenceEvidence outer concrete symbolic
      rightReceiverType name rightObservedTypes rightReturnType rightScheme
      rightInner rightResolved)
    (leftReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      leftSourceReceiver leftSourceGround leftSourceCore)
    (rightReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      rightSourceReceiver rightSourceGround rightSourceCore)
    (leftMemberBase : SymbolicMemberBase leftSourceReceiver leftReceiverType)
    (rightMemberBase : SymbolicMemberBase rightSourceReceiver rightReceiverType)
    (leftMemberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      leftSourceGround leftSourceCore leftResolved.receiverType leftReceiverCore)
    (rightMemberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      rightSourceGround rightSourceCore rightResolved.receiverType rightReceiverCore)
    (leftArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftObservedTypes leftResolved.argumentTypes leftCoreArguments)
    (rightArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightObservedTypes rightResolved.argumentTypes rightCoreArguments)
    (leftReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization leftResolved.receiverMode
      leftResolved.receiverType leftReceiverCore leftReceiverArgumentCore)
    (rightReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization rightResolved.receiverMode
      rightResolved.receiverType rightReceiverCore rightReceiverArgumentCore) :
    leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftReceiverArgumentCore = rightReceiverArgumentCore ∧
      leftCoreArguments = rightCoreArguments := by
  rcases receiverUnique leftReceiver rightReceiver with
    ⟨sourceTypeEquality, sourceGroundEquality, sourceCoreEquality⟩
  cases sourceTypeEquality
  cases sourceGroundEquality
  cases sourceCoreEquality
  have receiverTypeEquality := leftMemberBase.unique rightMemberBase
  cases receiverTypeEquality
  obtain ⟨observedTypesEquality, resolvedArgumentsEquality,
      coreArgumentsEquality⟩ :=
    argumentsUnique leftArguments rightArguments
  cases observedTypesEquality
  have resolvedReceiverEquality :
      leftResolved.receiverType = rightResolved.receiverType :=
    Option.some.inj (left.receiverGrounds.symm.trans right.receiverGrounds)
  have leftResolves := left.artifact.resolvesMethod contexts left.schemeMember
    left.schemeName left.memberMode left.genericArguments left.typeArgumentsGround
    left.constArgumentsGround left.requirements left.receiverMatch.substitutes
    left.receiverGrounds left.argumentMatches.substitutes left.argumentGrounds
    left.returnSubstitute left.returnGrounds rfl rfl rfl left.groundPreferred
    left.coherent
  have rightResolves := right.artifact.resolvesMethod contexts right.schemeMember
    right.schemeName right.memberMode right.genericArguments right.typeArgumentsGround
    right.constArgumentsGround right.requirements right.receiverMatch.substitutes
    right.receiverGrounds right.argumentMatches.substitutes right.argumentGrounds
    right.returnSubstitute right.returnGrounds rfl rfl rfl right.groundPreferred
    right.coherent
  rw [← resolvedReceiverEquality, ← resolvedArgumentsEquality] at rightResolves
  have sameFunction := leftResolves.2.2.2 rightScheme rightResolved
    rightResolves.1 rightResolves.2.1 rightResolves.2.2.1
  have leftMemberGlobal : leftResolved ∈
      symbolic.globals.methodInstances := by
    have member := leftResolves.2.1.1.1
    rw [contexts.globals] at member
    exact member
  have rightMemberGlobal : rightResolved ∈
      symbolic.globals.methodInstances := by
    have member := rightResolves.2.1.1.1
    rw [contexts.globals] at member
    exact member
  have resolvedEquality := complete.artifacts.methodInstanceIdsUnique
    leftResolved leftMemberGlobal rightResolved rightMemberGlobal
      sameFunction.symm
  have schemeEquality := left.coherent concrete.currentModule
    leftResolved.receiverType name leftScheme leftResolves.1
    ⟨leftResolved.argumentTypes, leftResolved, leftResolves.2.1.1⟩
    leftResolves.2.2.1 rightScheme rightResolves.1
    ⟨leftResolved.argumentTypes, rightResolved, rightResolves.2.1.1⟩
    rightResolves.2.2.1
  cases schemeEquality
  have leftMatches : Static.TypesSymbolicallyMatch leftInner
      (leftScheme.receiverType :: leftScheme.argumentTypes)
      (leftReceiverType :: leftObservedTypes) :=
    .cons left.receiverMatch left.argumentMatches
  have rightMatches : Static.TypesSymbolicallyMatch rightInner
      (leftScheme.receiverType :: leftScheme.argumentTypes)
      (leftReceiverType :: leftObservedTypes) :=
    .cons right.receiverMatch right.argumentMatches
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined leftMatches rightMatches left.genericArguments
      right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨_receiverTypeEquality, _argumentTypesEquality,
      returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique left.schemeMember
      left.genericArguments rightGenericArguments left.receiverMatch.substitutes
      right.receiverMatch.substitutes left.argumentMatches.substitutes
      right.argumentMatches.substitutes left.returnSubstitute
      right.returnSubstitute
  cases returnTypeEquality
  cases resolvedEquality
  have receiverCoreEquality :=
    leftMemberLowers.core_unique rightMemberLowers
  cases receiverCoreEquality
  have receiverArgumentEquality :=
    leftReceiverArgument.unique rightReceiverArgument
  exact ⟨rfl, rfl, receiverArgumentEquality, coreArgumentsEquality⟩

/-- Contextual method calls can infer generic arguments only from the receiver.
    That restriction fixes the symbolic signature before recursively checking
    arguments, so two contextual derivations select the same artifact and Core
    call. -/
theorem MethodCallContextualEvidence.results_unique_of_children
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (receiverUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (argumentsUnique : ∀ {expectedTypes leftGround leftCore rightGround
        rightCore},
      ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes leftGround leftCore →
        ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : MethodCallContextualEvidence outer concrete symbolic
      leftReceiverType name leftExpectedTypes leftReturnType leftScheme
      leftInner leftResolved)
    (right : MethodCallContextualEvidence outer concrete symbolic
      rightReceiverType name rightExpectedTypes rightReturnType rightScheme
      rightInner rightResolved)
    (leftReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      leftSourceReceiver leftSourceGround leftSourceCore)
    (rightReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      rightSourceReceiver rightSourceGround rightSourceCore)
    (leftMemberBase : SymbolicMemberBase leftSourceReceiver leftReceiverType)
    (rightMemberBase : SymbolicMemberBase rightSourceReceiver rightReceiverType)
    (leftMemberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      leftSourceGround leftSourceCore leftResolved.receiverType leftReceiverCore)
    (rightMemberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      rightSourceGround rightSourceCore rightResolved.receiverType rightReceiverCore)
    (leftArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftExpectedTypes leftResolved.argumentTypes leftCoreArguments)
    (rightArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightExpectedTypes rightResolved.argumentTypes rightCoreArguments)
    (leftReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization leftResolved.receiverMode
      leftResolved.receiverType leftReceiverCore leftReceiverArgumentCore)
    (rightReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization rightResolved.receiverMode
      rightResolved.receiverType rightReceiverCore rightReceiverArgumentCore) :
    leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftReceiverArgumentCore = rightReceiverArgumentCore ∧
      leftCoreArguments = rightCoreArguments := by
  rcases receiverUnique leftReceiver rightReceiver with
    ⟨sourceTypeEquality, sourceGroundEquality, sourceCoreEquality⟩
  cases sourceTypeEquality
  cases sourceGroundEquality
  cases sourceCoreEquality
  have receiverTypeEquality := leftMemberBase.unique rightMemberBase
  cases receiverTypeEquality
  have declarationEquality := left.unique rightScheme right.schemeMember
    ⟨rightInner, right.schemeName, right.receiverMatch,
      right.genericArguments.parametersBound, right.requirements.symbolic⟩
    right.symbolicPreferred
  have schemeEquality := complete.metadataUnique.methods leftScheme
    left.schemeMember rightScheme right.schemeMember declarationEquality.symm
  cases schemeEquality
  have leftMatches : Static.TypesSymbolicallyMatch leftInner
      [leftScheme.receiverType] [leftReceiverType] :=
    .cons left.receiverMatch .nil
  have rightMatches : Static.TypesSymbolicallyMatch rightInner
      [leftScheme.receiverType] [leftReceiverType] :=
    .cons right.receiverMatch .nil
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined leftMatches rightMatches left.genericArguments
      right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨_receiverTypeEquality, expectedTypesEquality, returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique left.schemeMember
      left.genericArguments rightGenericArguments left.receiverMatch.substitutes
      right.receiverMatch.substitutes left.argumentsSubstitute
      right.argumentsSubstitute left.returnSubstitute right.returnSubstitute
  cases expectedTypesEquality
  cases returnTypeEquality
  have resolvedReceiverEquality :
      leftResolved.receiverType = rightResolved.receiverType :=
    Option.some.inj (left.receiverGrounds.symm.trans right.receiverGrounds)
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have resolvedEquality := complete.concreteMethodArtifact_unique contexts
    resolvedReceiverEquality left.artifact right.artifact
    groundTypeArgumentsEquality groundConstArgumentsEquality
  cases resolvedEquality
  obtain ⟨_argumentGroundsEquality, coreArgumentsEquality⟩ :=
    argumentsUnique leftArguments rightArguments
  have receiverCoreEquality :=
    leftMemberLowers.core_unique rightMemberLowers
  cases receiverCoreEquality
  have receiverArgumentEquality :=
    leftReceiverArgument.unique rightReceiverArgument
  exact ⟨rfl, rfl, receiverArgumentEquality, coreArgumentsEquality⟩

/-- The inferred and contextual method rules agree whenever both apply. A
    contextual rule may infer generics only from the receiver, so its binding
    also agrees with the inferred rule; the inferred argument traversal can
    then be viewed as exact contextual checking at that shared signature. -/
theorem MethodCallInferenceEvidence.results_unique_of_contextual
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (receiverUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (argumentsUnique : ∀ {expectedTypes leftGround leftCore rightGround
        rightCore},
      ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes leftGround leftCore →
        ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (inferred : MethodCallInferenceEvidence outer concrete symbolic
      inferredReceiverType name observedTypes inferredReturnType inferredScheme
      inferredInner inferredResolved)
    (contextual : MethodCallContextualEvidence outer concrete symbolic
      contextualReceiverType name expectedTypes contextualReturnType
      contextualScheme contextualInner contextualResolved)
    (inferredReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      inferredSourceReceiver inferredSourceGround inferredSourceCore)
    (contextualReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      contextualSourceReceiver contextualSourceGround contextualSourceCore)
    (inferredMemberBase : SymbolicMemberBase inferredSourceReceiver
      inferredReceiverType)
    (contextualMemberBase : SymbolicMemberBase contextualSourceReceiver
      contextualReceiverType)
    (inferredMemberLowers : Elaboration.MemberBaseLowers
      concrete.monomorphization inferredSourceGround inferredSourceCore
      inferredResolved.receiverType inferredReceiverCore)
    (contextualMemberLowers : Elaboration.MemberBaseLowers
      concrete.monomorphization contextualSourceGround contextualSourceCore
      contextualResolved.receiverType contextualReceiverCore)
    (inferredArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      observedTypes inferredResolved.argumentTypes inferredCoreArguments)
    (contextualArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      expectedTypes contextualResolved.argumentTypes contextualCoreArguments)
    (inferredReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization inferredResolved.receiverMode
      inferredResolved.receiverType inferredReceiverCore
      inferredReceiverArgumentCore)
    (contextualReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization contextualResolved.receiverMode
      contextualResolved.receiverType contextualReceiverCore
      contextualReceiverArgumentCore) :
    inferredReturnType = contextualReturnType ∧
      inferredResolved = contextualResolved ∧
      inferredReceiverArgumentCore = contextualReceiverArgumentCore ∧
      inferredCoreArguments = contextualCoreArguments := by
  rcases receiverUnique inferredReceiver contextualReceiver with
    ⟨sourceTypeEquality, sourceGroundEquality, sourceCoreEquality⟩
  cases sourceTypeEquality
  cases sourceGroundEquality
  cases sourceCoreEquality
  have receiverTypeEquality :=
    inferredMemberBase.unique contextualMemberBase
  cases receiverTypeEquality
  have declarationEquality := contextual.unique inferredScheme
    inferred.schemeMember
    ⟨inferredInner, inferred.schemeName, inferred.receiverMatch,
      inferred.genericArguments.parametersBound, inferred.requirements.symbolic⟩
    inferred.symbolicPreferred
  have schemeEquality := complete.metadataUnique.methods inferredScheme
    inferred.schemeMember contextualScheme contextual.schemeMember
    declarationEquality
  cases schemeEquality
  have inferredMatches : Static.TypesSymbolicallyMatch inferredInner
      [inferredScheme.receiverType] [inferredReceiverType] :=
    .cons inferred.receiverMatch .nil
  have contextualMatches : Static.TypesSymbolicallyMatch contextualInner
      [inferredScheme.receiverType] [inferredReceiverType] :=
    .cons contextual.receiverMatch .nil
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      contextual.determined inferredMatches contextualMatches
      inferred.genericArguments contextual.genericArguments
  have contextualGenericArguments : Static.SymbolicArgumentsBound
      contextualInner inferredScheme.genericParameters
      inferred.symbolicTypeArguments inferred.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact contextual.genericArguments
  obtain ⟨_receiverTypeEquality, argumentTypesEquality, returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique inferred.schemeMember
      inferred.genericArguments contextualGenericArguments
      inferred.receiverMatch.substitutes contextual.receiverMatch.substitutes
      inferred.argumentMatches.substitutes contextual.argumentsSubstitute
      inferred.returnSubstitute contextual.returnSubstitute
  cases argumentTypesEquality
  cases returnTypeEquality
  have resolvedReceiverEquality :
      inferredResolved.receiverType = contextualResolved.receiverType :=
    Option.some.inj
      (inferred.receiverGrounds.symm.trans contextual.receiverGrounds)
  have groundTypeArgumentsEquality := Option.some.inj
    (inferred.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        contextual.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (inferred.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans contextual.constArgumentsGround))
  have resolvedEquality := complete.concreteMethodArtifact_unique contexts
    resolvedReceiverEquality inferred.artifact contextual.artifact
    groundTypeArgumentsEquality groundConstArgumentsEquality
  cases resolvedEquality
  obtain ⟨_argumentGroundsEquality, coreArgumentsEquality⟩ :=
    argumentsUnique inferredArguments.asChecking contextualArguments
  have receiverCoreEquality :=
    inferredMemberLowers.core_unique contextualMemberLowers
  cases receiverCoreEquality
  have receiverArgumentEquality :=
    inferredReceiverArgument.unique contextualReceiverArgument
  exact ⟨rfl, rfl, receiverArgumentEquality, coreArgumentsEquality⟩

/-- Match-arm traversal is functional once pattern specialization and body
    checking are. Pattern functionality aligns the exact binding rows before
    the body theorem is invoked under the extended contexts. -/
theorem MatchArmsDerivationSpecializes.unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (patternUnique : ∀ {nextCase surfacePattern symbolicType groundType
        leftPattern leftSymbolicBindings leftConcreteBindings leftFinal
        rightPattern rightSymbolicBindings rightConcreteBindings rightFinal},
      PatternDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts nextCase surfacePattern symbolicType groundType leftPattern
          leftSymbolicBindings leftConcreteBindings leftFinal →
        PatternDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts nextCase surfacePattern symbolicType groundType rightPattern
          rightSymbolicBindings rightConcreteBindings rightFinal →
        leftPattern = rightPattern ∧
          leftSymbolicBindings = rightSymbolicBindings ∧
          leftConcreteBindings = rightConcreteBindings ∧
          leftFinal = rightFinal)
    (exprUnique : ∀ {bodySymbolic : SymbolicBodyContext}
        {bodyConcrete : SurfaceElaboration.Context}
        {bodyContexts : bodySymbolic.Specializes outer groundEnclosingReturn
          bodyConcrete}
        {surfaceExpr expected leftGround leftCore rightGround rightCore},
      CompleteProgramElaboration pack catalog imports program
          bodySymbolic.globals externalBindings →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn
          bodySymbolic bodyConcrete bodyContexts surfaceExpr expected leftGround
          leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn
          bodySymbolic bodyConcrete bodyContexts surfaceExpr expected rightGround
          rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : MatchArmsDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts next symbolicScrutinee symbolicResult groundScrutinee
      groundResult surfaceArms leftCore)
    (right : MatchArmsDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts next symbolicScrutinee symbolicResult groundScrutinee
      groundResult surfaceArms rightCore) :
    leftCore = rightCore := by
  induction surfaceArms generalizing leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons surfaceArm surfaceTail induction =>
      cases left with
      | @cons symbolicCase concreteCase contextsCase nextCase surfacePatternCase
          symbolicScrutineeCase groundScrutineeCase corePatternCase
          symbolicBindingsCase concreteBindingsCase patternFinalCase
          surfaceBodyCase symbolicResultCase groundResultCase coreBodyCase
          surfaceTailCase coreTailCase leftPattern leftBody leftTail =>
          cases right with
          | cons rightPattern rightBody rightTail =>
              rcases patternUnique leftPattern rightPattern with
                ⟨corePatternEquality, symbolicBindingsEquality,
                  concreteBindingsEquality, finalEquality⟩
              cases corePatternEquality
              cases symbolicBindingsEquality
              cases concreteBindingsEquality
              cases finalEquality
              have bodyContextsEquality : leftPattern.boundContexts =
                  rightPattern.boundContexts := Subsingleton.elim _ _
              cases bodyContextsEquality
              have bodyComplete : CompleteProgramElaboration pack catalog imports
                  program (symbolic.bindMany symbolicBindingsCase).globals
                  externalBindings :=
                by
                  simpa [SymbolicBodyContext.bindMany_eq] using complete
              obtain ⟨_groundBodyEquality, coreBodyEquality⟩ := exprUnique
                  (bodySymbolic := symbolic.bindMany symbolicBindingsCase)
                  (bodyConcrete := concrete.bindLocals concreteBindingsCase)
                  (bodyContexts := leftPattern.boundContexts)
                  bodyComplete leftBody rightBody
              cases coreBodyEquality
              cases induction leftTail rightTail
              rfl

/-- Recursive place specialization is functional assuming expression
    inference is functional for index expressions. This proof recurses only
    over the strictly smaller emitted base place, so it need not join the large
    generated mutual recursor. -/
private def placeDepth : Core.Place → Nat
  | .local _ => 0
  | .field base _ => placeDepth base + 1
  | .index base _ => placeDepth base + 1

theorem PlaceDerivationSpecializes.unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (exprUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surface leftSymbolic leftGround leftCore)
    (right : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surface rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | «local» leftSingle leftSymbolicResolved leftConcreteResolved
      leftTypeGrounds =>
      cases right with
      | «local» rightSingle rightSymbolicResolved rightConcreteResolved
          rightTypeGrounds =>
          have nameEquality := Option.some.inj
            (leftSingle.symm.trans rightSingle)
          cases nameEquality
          cases leftSymbolicResolved.unique rightSymbolicResolved
          cases leftConcreteResolved.unique rightConcreteResolved
          exact ⟨rfl, rfl, rfl⟩
  | selfValue leftSymbolicResolved leftConcreteResolved leftTypeGrounds =>
      cases right with
      | selfValue rightSymbolicResolved rightConcreteResolved rightTypeGrounds =>
          cases leftSymbolicResolved.unique rightSymbolicResolved
          cases leftConcreteResolved.unique rightConcreteResolved
          exact ⟨rfl, rfl, rfl⟩
  | field leftBase leftSymbolicSelected leftConcreteSelected leftFieldGrounds =>
      cases right with
      | field rightBase rightSymbolicSelected rightConcreteSelected
          rightFieldGrounds =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete exprUnique
              leftBase rightBase with
            ⟨receiverTypeEquality, groundReceiverEquality, coreBaseEquality⟩
          cases receiverTypeEquality
          cases groundReceiverEquality
          cases coreBaseEquality
          cases complete.symbolicFieldResult_unique leftSymbolicSelected
            rightSymbolicSelected
          cases leftConcreteSelected.unique rightConcreteSelected
          exact ⟨rfl, rfl, rfl⟩
  | indexArray leftBase leftElementGrounds leftLengthGrounds leftIndex
      leftInteger =>
      cases right with
      | indexArray rightBase rightElementGrounds rightLengthGrounds rightIndex
          rightInteger =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete exprUnique
              leftBase rightBase with
            ⟨baseTypeEquality, baseGroundEquality, coreBaseEquality⟩
          injection baseTypeEquality with elementTypeEquality lengthEquality
          injection baseGroundEquality with groundElementEquality
            groundLengthEquality
          cases elementTypeEquality
          cases lengthEquality
          cases groundElementEquality
          cases groundLengthEquality
          cases coreBaseEquality
          rcases exprUnique leftIndex rightIndex with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | indexSlice rightBase rightElementGrounds rightIndex rightInteger =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete exprUnique
              leftBase rightBase with ⟨baseTypeEquality, _, _⟩
          cases baseTypeEquality
  | indexSlice leftBase leftElementGrounds leftIndex leftInteger =>
      cases right with
      | indexArray rightBase rightElementGrounds rightLengthGrounds rightIndex
          rightInteger =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete exprUnique
              leftBase rightBase with ⟨baseTypeEquality, _, _⟩
          cases baseTypeEquality
      | indexSlice rightBase rightElementGrounds rightIndex rightInteger =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete exprUnique
              leftBase rightBase with
            ⟨baseTypeEquality, baseGroundEquality, coreBaseEquality⟩
          injection baseTypeEquality with elementTypeEquality
          injection baseGroundEquality with groundElementEquality
          cases elementTypeEquality
          cases groundElementEquality
          cases coreBaseEquality
          rcases exprUnique leftIndex rightIndex with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
termination_by placeDepth leftCore
decreasing_by
  all_goals
    subst leftCore
    simp [placeDepth]

/-- Assignment inference is functional once place inference and contextual value
    checking are functional. The assignment operator never contributes a hidden
    result choice: every successful assignment has unit type and emits the Core
    place and value selected by those two child judgments. -/
theorem ExprInferenceDerivationSpecializes.assign_unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.assign op surfacePlace surfaceValue)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.assign op surfacePlace surfaceValue)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | assign leftPlace leftValue leftCoreGrounds leftTyped =>
      cases right with
      | assign rightPlace rightValue rightCoreGrounds rightTyped =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete inferUnique
              leftPlace rightPlace with ⟨rfl, rfl, rfl⟩
          obtain ⟨_groundValueEquality, coreValueEquality⟩ :=
            checkUnique leftValue rightValue
          cases coreValueEquality
          exact ⟨rfl, rfl, rfl⟩

/-- In a complete program, recursive exact pattern specialization is a
    function. One source pattern, symbolic type, context, substitution, and
    incoming local-ID supply determine the ground type, emitted core pattern,
    both binding tables, and outgoing supply. -/
theorem CompleteProgramElaboration.patternSpecialization_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundTypeLeft
      coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft)
    (right : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundTypeRight
      coreRight symbolicBindingsRight concreteBindingsRight finalRight) :
    groundTypeLeft = groundTypeRight ∧ coreLeft = coreRight ∧
      symbolicBindingsLeft = symbolicBindingsRight ∧
      concreteBindingsLeft = concreteBindingsRight ∧ finalLeft = finalRight := by
  refine PatternDerivationSpecializes.rec
    (motive_1 := fun symbolic concreteCase contextsCase next surface symbolicType
        groundLeft coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft _ =>
      CompleteProgramElaboration pack catalog imports program symbolic.globals
          externalBindings →
        ∀ groundRight coreRight symbolicBindingsRight concreteBindingsRight
            finalRight,
          PatternDerivationSpecializes outer groundEnclosingReturn symbolic
              concreteCase contextsCase next surface symbolicType groundRight coreRight
              symbolicBindingsRight concreteBindingsRight finalRight →
            groundLeft = groundRight ∧ coreLeft = coreRight ∧
              symbolicBindingsLeft = symbolicBindingsRight ∧
              concreteBindingsLeft = concreteBindingsRight ∧
              finalLeft = finalRight)
    (motive_2 := fun symbolic concreteCase contextsCase next surfaces symbolicTypes
        groundLeft coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft _ =>
      CompleteProgramElaboration pack catalog imports program symbolic.globals
          externalBindings →
        ∀ groundRight coreRight symbolicBindingsRight concreteBindingsRight
            finalRight,
          PatternListDerivationSpecializes outer groundEnclosingReturn symbolic
              concreteCase contextsCase next surfaces symbolicTypes groundRight coreRight
              symbolicBindingsRight concreteBindingsRight finalRight →
            groundLeft = groundRight ∧ coreLeft = coreRight ∧
              symbolicBindingsLeft = symbolicBindingsRight ∧
              concreteBindingsLeft = concreteBindingsRight ∧
              finalLeft = finalRight)
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ left complete _ _ _ _ _ right
  · intro groundType symbolicCase concreteCase contextsCase nextCase symbolicType
      leftGrounds completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | wildcard rightGrounds =>
        have groundEquality := Option.some.inj
          (leftGrounds.symm.trans rightGrounds)
        subst groundRight
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro path name groundType concreteCase nextCase symbolicCase contextsCase
      symbolicType leftSingle leftNotVariant leftGrounds leftBounded completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase with
    | bind rightSingle rightNotVariant rightGrounds rightBounded =>
        have nameEquality := Option.some.inj
          (leftSingle.symm.trans rightSingle)
        cases nameEquality
        have groundEquality := Option.some.inj
          (leftGrounds.symm.trans rightGrounds)
        subst groundRight
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
    | variant rightReceiver rightSelected rightArguments
        rightTypeArgumentsGround rightConstArgumentsGround
        rightPayloadSubstitute rightPayload rightArtifact rightBounded =>
        obtain ⟨symbol, resolved, _member, _declaration, _unique⟩ :=
          rightSelected.2.2
        exact (leftNotVariant symbol resolved).elim
  · intro text scalar value symbolicCase concreteCase contextsCase nextCase
      leftLowered completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | integer rightLowered =>
        cases leftLowered.core_unique rightLowered
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase value completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicType symbolicCase path constructor inner symbolicTypeArguments
      symbolicConstArguments groundTypeArguments groundConstArguments
      expectedPayload concreteCase contextsCase nextCase surfacePayload
      groundPayload corePayload symbolicBindings concreteBindings final entry
      leftReceiver leftSelected leftArguments leftTypeArgumentsGround
      leftConstArgumentsGround leftPayloadSubstitute leftPayload leftArtifact
      leftBounded payloadInduction completeCase groundRight coreRight
      symbolicBindingsRight concreteBindingsRight finalRight rightCase
    cases rightCase with
    | bind rightSingle rightNotVariant rightGrounds rightBounded =>
        obtain ⟨symbol, resolved, _member, _declaration, _unique⟩ :=
          leftSelected.2.2
        exact (rightNotVariant symbol resolved).elim
    | variant rightReceiver rightSelected rightArguments
        rightTypeArgumentsGround rightConstArgumentsGround
        rightPayloadSubstitute rightPayload rightArtifact rightBounded =>
        cases completeCase.symbolicVariantConstructor_unique
          leftSelected rightSelected
        have receiverEquality := leftReceiver.symm.trans rightReceiver
        injection receiverEquality with sourceTypeEquality
          symbolicTypeArgumentsEquality symbolicConstArgumentsEquality
        cases sourceTypeEquality
        cases symbolicTypeArgumentsEquality
        cases symbolicConstArgumentsEquality
        obtain ⟨symbol, resolved, constructorMember, declaration, unique⟩ :=
          leftSelected.2.2
        have expectedPayloadEquality :=
          completeCase.variantPayloadSubstitute_unique constructorMember
            leftArguments rightArguments leftPayloadSubstitute
            rightPayloadSubstitute
        cases expectedPayloadEquality
        rcases payloadInduction completeCase _ _ _ _ _ rightPayload with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        have typeArgumentsEquality := Option.some.inj
          (leftTypeArgumentsGround.symm.trans rightTypeArgumentsGround)
        have constArgumentsEquality := Option.some.inj
          (leftConstArgumentsGround.symm.trans rightConstArgumentsGround)
        cases typeArgumentsEquality
        cases constArgumentsEquality
        obtain ⟨coreTypeEquality, variantEquality, _payloadEquality⟩ :=
          leftArtifact.agrees rightArtifact
        exact ⟨rfl, by simp [coreTypeEquality, variantEquality],
          rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase surfaceHead symbolicHead
      groundHead coreHead symbolicHeadBindings concreteHeadBindings middle
      surfaceTail symbolicTail groundTail coreTail symbolicTailBindings
      concreteTailBindings final leftHead leftTail leftDistinct headInduction
      tailInduction completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | cons rightHead rightTail rightDistinct =>
        rcases headInduction completeCase _ _ _ _ _ rightHead with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        rcases tailInduction completeCase _ _ _ _ _ rightTail with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- The corresponding functionality theorem for recursive pattern lists. -/
theorem CompleteProgramElaboration.patternListSpecialization_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : PatternListDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surfaces symbolicTypes groundTypesLeft
      coresLeft symbolicBindingsLeft concreteBindingsLeft finalLeft)
    (right : PatternListDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surfaces symbolicTypes groundTypesRight
      coresRight symbolicBindingsRight concreteBindingsRight finalRight) :
    groundTypesLeft = groundTypesRight ∧ coresLeft = coresRight ∧
      symbolicBindingsLeft = symbolicBindingsRight ∧
      concreteBindingsLeft = concreteBindingsRight ∧ finalLeft = finalRight := by
  refine PatternListDerivationSpecializes.rec
    (motive_1 := fun symbolic concreteCase contextsCase next surface symbolicType
        groundLeft coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft _ =>
      CompleteProgramElaboration pack catalog imports program symbolic.globals
          externalBindings →
        ∀ groundRight coreRight symbolicBindingsRight concreteBindingsRight
            finalRight,
          PatternDerivationSpecializes outer groundEnclosingReturn symbolic
              concreteCase contextsCase next surface symbolicType groundRight coreRight
              symbolicBindingsRight concreteBindingsRight finalRight →
            groundLeft = groundRight ∧ coreLeft = coreRight ∧
              symbolicBindingsLeft = symbolicBindingsRight ∧
              concreteBindingsLeft = concreteBindingsRight ∧
              finalLeft = finalRight)
    (motive_2 := fun symbolic concreteCase contextsCase next surfaces symbolicTypes
        groundLeft coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft _ =>
      CompleteProgramElaboration pack catalog imports program symbolic.globals
          externalBindings →
        ∀ groundRight coreRight symbolicBindingsRight concreteBindingsRight
            finalRight,
          PatternListDerivationSpecializes outer groundEnclosingReturn symbolic
              concreteCase contextsCase next surfaces symbolicTypes groundRight coreRight
              symbolicBindingsRight concreteBindingsRight finalRight →
            groundLeft = groundRight ∧ coreLeft = coreRight ∧
              symbolicBindingsLeft = symbolicBindingsRight ∧
              concreteBindingsLeft = concreteBindingsRight ∧
              finalLeft = finalRight)
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ left complete _ _ _ _ _ right
  · intro groundType symbolicCase concreteCase contextsCase nextCase symbolicType
      leftGrounds completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | wildcard rightGrounds =>
        have groundEquality := Option.some.inj
          (leftGrounds.symm.trans rightGrounds)
        subst groundRight
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro path name groundType concreteCase nextCase symbolicCase contextsCase
      symbolicType leftSingle leftNotVariant leftGrounds leftBounded completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase with
    | bind rightSingle rightNotVariant rightGrounds rightBounded =>
        have nameEquality := Option.some.inj
          (leftSingle.symm.trans rightSingle)
        cases nameEquality
        have groundEquality := Option.some.inj
          (leftGrounds.symm.trans rightGrounds)
        subst groundRight
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
    | variant rightReceiver rightSelected rightArguments
        rightTypeArgumentsGround rightConstArgumentsGround
        rightPayloadSubstitute rightPayload rightArtifact rightBounded =>
        obtain ⟨symbol, resolved, _member, _declaration, _unique⟩ :=
          rightSelected.2.2
        exact (leftNotVariant symbol resolved).elim
  · intro text scalar value symbolicCase concreteCase contextsCase nextCase
      leftLowered completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | integer rightLowered =>
        cases leftLowered.core_unique rightLowered
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase value completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicType symbolicCase path constructor inner symbolicTypeArguments
      symbolicConstArguments groundTypeArguments groundConstArguments
      expectedPayload concreteCase contextsCase nextCase surfacePayload
      groundPayload corePayload symbolicBindings concreteBindings final entry
      leftReceiver leftSelected leftArguments leftTypeArgumentsGround
      leftConstArgumentsGround leftPayloadSubstitute leftPayload leftArtifact
      leftBounded payloadInduction completeCase groundRight coreRight
      symbolicBindingsRight concreteBindingsRight finalRight rightCase
    cases rightCase with
    | bind rightSingle rightNotVariant rightGrounds rightBounded =>
        obtain ⟨symbol, resolved, _member, _declaration, _unique⟩ :=
          leftSelected.2.2
        exact (rightNotVariant symbol resolved).elim
    | variant rightReceiver rightSelected rightArguments
        rightTypeArgumentsGround rightConstArgumentsGround
        rightPayloadSubstitute rightPayload rightArtifact rightBounded =>
        cases completeCase.symbolicVariantConstructor_unique
          leftSelected rightSelected
        have receiverEquality := leftReceiver.symm.trans rightReceiver
        injection receiverEquality with sourceTypeEquality
          symbolicTypeArgumentsEquality symbolicConstArgumentsEquality
        cases sourceTypeEquality
        cases symbolicTypeArgumentsEquality
        cases symbolicConstArgumentsEquality
        obtain ⟨symbol, resolved, constructorMember, declaration, unique⟩ :=
          leftSelected.2.2
        have expectedPayloadEquality :=
          completeCase.variantPayloadSubstitute_unique constructorMember
            leftArguments rightArguments leftPayloadSubstitute
            rightPayloadSubstitute
        cases expectedPayloadEquality
        rcases payloadInduction completeCase _ _ _ _ _ rightPayload with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        have typeArgumentsEquality := Option.some.inj
          (leftTypeArgumentsGround.symm.trans rightTypeArgumentsGround)
        have constArgumentsEquality := Option.some.inj
          (leftConstArgumentsGround.symm.trans rightConstArgumentsGround)
        cases typeArgumentsEquality
        cases constArgumentsEquality
        obtain ⟨coreTypeEquality, variantEquality, _payloadEquality⟩ :=
          leftArtifact.agrees rightArtifact
        exact ⟨rfl, by simp [coreTypeEquality, variantEquality],
          rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase surfaceHead symbolicHead
      groundHead coreHead symbolicHeadBindings concreteHeadBindings middle
      surfaceTail symbolicTail groundTail coreTail symbolicTailBindings
      concreteTailBindings final leftHead leftTail leftDistinct headInduction
      tailInduction completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | cons rightHead rightTail rightDistinct =>
        rcases headInduction completeCase _ _ _ _ _ rightHead with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        rcases tailInduction completeCase _ _ _ _ _ rightTail with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩

def SelectsEntrypointHeader
    (catalog : Declarations.Catalog)
    (selected : Declarations.DeclarationHeader) : Prop :=
  selected ∈ catalog.headers ∧
    selected.kind = .function ∧
    selected.name = some "main" ∧
    ∀ candidate,
      candidate ∈ catalog.headers →
      candidate.kind = .function →
      candidate.name = some "main" →
      candidate.declaration = selected.declaration

inductive EntrypointLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (executable : Execution.Executable) : Prop where
  | intro
      (header : Declarations.DeclarationHeader)
      (scheme : Static.FunctionScheme)
      (resolved : Static.FunctionInstance)
      (core : Core.Function)
      (selected : SelectsEntrypointHeader catalog header)
      (lowered : CollectedFunctionLowers pack catalog program context header scheme
        resolved core)
      (noParameters : core.parameters = [])
      (returnType : Execution.EntrypointReturnType core.returnType)
      (executableProgram : executable.program = program)
      (executableEntrypoint : executable.entrypoint = core.id)
      (wellFormed : Execution.ExecutableWellFormed executable) :
      EntrypointLowers pack catalog program context executable

structure CompleteExecutableElaboration
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (externalBindings : List ExternalBinding)
    (executable : Execution.Executable) : Prop where
  programElaboration : CompleteProgramElaboration pack catalog imports program
    context externalBindings
  entrypoint : EntrypointLowers pack catalog program context executable

end Lanius.ProgramElaboration
