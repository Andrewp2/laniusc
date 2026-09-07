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
    | i32SliceFromRawParts
        (builtin : SurfaceElaboration.builtinIntrinsic? path =
          some .i32SliceFromRawParts)
        (pointer : SymbolicExprChecks context surfacePointer (.scalar .rawPtr))
        (length : SymbolicExprChecks context surfaceLength
          (.scalar (.signed .i32))) :
        SymbolicExprInfers context
          (.call (.path path) [surfacePointer, surfaceLength])
          (.slice (.scalar (.signed .i32)))
    | i32SliceDataPtr
        (builtin : SurfaceElaboration.builtinIntrinsic? path =
          some .i32SliceDataPtr)
        (slice : SymbolicExprChecks context surfaceSlice
          (.slice (.scalar (.signed .i32)))) :
        SymbolicExprInfers context
          (.call (.path path) [surfaceSlice]) (.scalar .rawPtr)
    | stringDataPtr
        (builtin : SurfaceElaboration.builtinIntrinsic? path =
          some .stringDataPtr)
        (string : SymbolicExprChecks context surfaceString (.scalar .string)) :
        SymbolicExprInfers context
          (.call (.path path) [surfaceString]) (.scalar .rawPtr)
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

theorem SymbolicExprInfers.i32SliceFromRawPartsSpecializes
    (builtin : SurfaceElaboration.builtinIntrinsic? path =
      some .i32SliceFromRawParts)
    (pointer : ExprCheckSpecializes substitution concrete surfacePointer
      (.scalar .rawPtr))
    (length : ExprCheckSpecializes substitution concrete surfaceLength
      (.scalar (.signed .i32))) :
    ExprSpecializes substitution concrete
      (.call (.path path) [surfacePointer, surfaceLength])
      (.slice (.scalar (.signed .i32))) := by
  obtain ⟨groundPointer, corePointer, pointerGrounds, pointerChecks⟩ := pointer
  obtain ⟨groundLength, coreLength, lengthGrounds, lengthChecks⟩ := length
  simp [Static.Ty.instantiate] at pointerGrounds lengthGrounds
  subst groundPointer
  subst groundLength
  exact .intro (.slice (.scalar (.signed .i32)))
    (.i32SliceFromRawParts corePointer coreLength) rfl
    (.i32SliceFromRawParts rfl builtin pointerChecks lengthChecks)

theorem SymbolicExprInfers.i32SliceDataPtrSpecializes
    (builtin : SurfaceElaboration.builtinIntrinsic? path =
      some .i32SliceDataPtr)
    (slice : ExprCheckSpecializes substitution concrete surfaceSlice
      (.slice (.scalar (.signed .i32)))) :
    ExprSpecializes substitution concrete
      (.call (.path path) [surfaceSlice]) (.scalar .rawPtr) := by
  obtain ⟨groundSlice, coreSlice, sliceGrounds, sliceChecks⟩ := slice
  simp [Static.Ty.instantiate] at sliceGrounds
  subst groundSlice
  exact .intro (.scalar .rawPtr) (.i32SliceDataPtr coreSlice) rfl
    (.i32SliceDataPtr rfl builtin sliceChecks)

theorem SymbolicExprInfers.stringDataPtrSpecializes
    (builtin : SurfaceElaboration.builtinIntrinsic? path = some .stringDataPtr)
    (string : ExprCheckSpecializes substitution concrete surfaceString
      (.scalar .string)) :
    ExprSpecializes substitution concrete
      (.call (.path path) [surfaceString]) (.scalar .rawPtr) := by
  obtain ⟨groundString, coreString, stringGrounds, stringChecks⟩ := string
  simp [Static.Ty.instantiate] at stringGrounds
  subst groundString
  exact .intro (.scalar .rawPtr) (.stringDataPtr coreString) rfl
    (.stringDataPtr rfl builtin stringChecks)

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
    | i32SliceFromRawParts
        (builtin : SurfaceElaboration.builtinIntrinsic? path =
          some .i32SliceFromRawParts)
        (pointer : ExprCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfacePointer
          (.scalar .rawPtr) (.scalar .rawPtr) corePointer)
        (length : ExprCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceLength
          (.scalar (.signed .i32)) (.scalar (.signed .i32)) coreLength) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) [surfacePointer, surfaceLength])
          (.slice (.scalar (.signed .i32))) (.slice (.scalar (.signed .i32)))
          (.i32SliceFromRawParts corePointer coreLength)
    | i32SliceDataPtr
        (builtin : SurfaceElaboration.builtinIntrinsic? path =
          some .i32SliceDataPtr)
        (slice : ExprCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceSlice
          (.slice (.scalar (.signed .i32))) (.slice (.scalar (.signed .i32)))
          coreSlice) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) [surfaceSlice])
          (.scalar .rawPtr) (.scalar .rawPtr) (.i32SliceDataPtr coreSlice)
    | stringDataPtr
        (builtin : SurfaceElaboration.builtinIntrinsic? path = some .stringDataPtr)
        (string : ExprCheckingDerivationSpecializes outer
          groundEnclosingReturn symbolic concrete contexts surfaceString
          (.scalar .string) (.scalar .string) coreString) :
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts (.call (.path path) [surfaceString])
          (.scalar .rawPtr) (.scalar .rawPtr) (.stringDataPtr coreString)
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
        (symbolicElements : SymbolicExprsCheck symbolic surfaceElements
          (List.replicate surfaceElements.length elementType))
        (concreteElements : SurfaceElaboration.ExprsCheck concrete
          surfaceElements (List.replicate surfaceElements.length groundElement)
          coreElements)
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

private theorem exactSymbolicSignedMinimum
    (lowered : Elaboration.SignedMinimumLiteralElaborates
      symbolic.globals.target text .i32 coreExpression) :
    SymbolicExprInfers symbolic
      (.unary .negative (.literal (.integer text)))
      (.scalar (.signed .i32)) :=
  .signedMinimumLiteral ⟨coreExpression, lowered⟩

private theorem exactSymbolicUnary
    (operand : SymbolicExprInfers symbolic surfaceOperand (.scalar inputType))
    (typed : Typing.UnaryOpHasType (SurfaceElaboration.lowerUnaryOp op)
      (.scalar inputType) (.scalar outputType)) :
    SymbolicExprInfers symbolic (.unary op surfaceOperand)
      (.scalar outputType) :=
  .unary operand (.scalar typed)

private theorem exactSymbolicBinary
    (left : SymbolicExprInfers symbolic surfaceLeft (.scalar leftType))
    (right : SymbolicExprInfers symbolic surfaceRight (.scalar rightType))
    (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar leftType) (.scalar rightType) (.scalar outputType)) :
    SymbolicExprInfers symbolic (.binary op surfaceLeft surfaceRight)
      (.scalar outputType) :=
  .binary left right (.exact typed)

private theorem exactSymbolicBinaryRightCast
    (left : SymbolicExprInfers symbolic surfaceLeft (.scalar leftType))
    (right : SymbolicExprInfers symbolic surfaceRight (.scalar rightType))
    (different : rightType ≠ leftType)
    (notPreferred : ¬ Typing.RightDominatesBinary leftType rightType)
    (conversion : Typing.ScalarCast rightType leftType)
    (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar leftType) (.scalar leftType) (.scalar outputType)) :
    SymbolicExprInfers symbolic (.binary op surfaceLeft surfaceRight)
      (.scalar outputType) :=
  .binary left right (.rightCast different notPreferred conversion typed)

private theorem exactSymbolicBinaryLeftCast
    (left : SymbolicExprInfers symbolic surfaceLeft (.scalar leftType))
    (right : SymbolicExprInfers symbolic surfaceRight (.scalar rightType))
    (preferred : Typing.RightDominatesBinary leftType rightType)
    (conversion : Typing.ScalarCast leftType rightType)
    (typed : Typing.BinaryOpHasType (SurfaceElaboration.lowerBinaryOp op)
      (.scalar rightType) (.scalar rightType) (.scalar outputType)) :
    SymbolicExprInfers symbolic (.binary op surfaceLeft surfaceRight)
      (.scalar outputType) :=
  .binary left right (.leftCast preferred conversion typed)

private theorem exactSymbolicLiteralChecks
    (lowered : Elaboration.LiteralElaborates symbolic.globals.target literal
      (.scalar scalarType) coreExpression) :
    SymbolicExprChecks symbolic (.literal literal) (.scalar scalarType) :=
  .literal ⟨scalarType, coreExpression, rfl, lowered⟩

private theorem exactSymbolicSignedMinimumChecks
    (lowered : Elaboration.SignedMinimumLiteralElaborates
      symbolic.globals.target text signedType coreExpression) :
    SymbolicExprChecks symbolic
      (.unary .negative (.literal (.integer text)))
      (.scalar (.signed signedType)) :=
  .signedMinimumLiteral rfl ⟨coreExpression, lowered⟩

private theorem exactSymbolicUnaryLiteralChecks
    (lowered : Elaboration.LiteralElaborates symbolic.globals.target literal
      (.scalar scalarType) coreOperand)
    (typed : Typing.UnaryOpHasType (SurfaceElaboration.lowerUnaryOp op)
      (.scalar scalarType) (.scalar scalarType)) :
    SymbolicExprChecks symbolic (.unary op (.literal literal))
      (.scalar scalarType) :=
  .unaryLiteral rfl ⟨coreOperand, lowered⟩ typed

private theorem exactSymbolicStructChecks
    (selected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path constructor)
    (expected : expectedType = .nominal constructor.sourceType
      symbolicTypeArguments symbolicConstArguments)
    (arguments : Static.SymbolicArgumentsBound inner
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (pathArguments : SymbolicPathArgumentsCompatible symbolic.globals path
      constructor.genericParameters inner)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer inner
      constructor.requirements)
    (fields : SymbolicStructFieldsCheck symbolic inner constructor.fields
      surfaceFields) :
    SymbolicExprChecks symbolic (.structValue path surfaceFields) expectedType :=
  .structValue selected expected arguments pathArguments requirements.symbolic
    fields

private theorem exactSymbolicVariantChecks
    (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
    (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
    (expected : expectedType = .nominal constructor.sourceType
      symbolicTypeArguments symbolicConstArguments)
    (arguments : Static.SymbolicArgumentsBound inner
      constructor.genericParameters symbolicTypeArguments symbolicConstArguments)
    (pathArguments : SymbolicPathArgumentsCompatible symbolic.globals path
      constructor.genericParameters inner)
    (requirements : Static.SymbolicRequirementsGround
      symbolic.globals.implementations symbolic.assumptions outer inner
      constructor.requirements)
    (payload : SymbolicExprsSubstitutedCheck symbolic inner surfaceArguments
      constructor.payload) :
    SymbolicExprChecks symbolic (.call (.path path) surfaceArguments)
      expectedType :=
  .variantCall selected notIntrinsic expected arguments pathArguments
    requirements.symbolic payload

set_option maxHeartbeats 1000000

local macro "deriveSymbolicProjection" outerSubstitution:ident
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
      first
      | (apply exactSymbolicSignedMinimum <;> assumption)
      | (apply exactSymbolicUnary <;> assumption)
      | (apply exactSymbolicBinaryRightCast <;> assumption)
      | (apply exactSymbolicBinaryLeftCast <;> assumption)
      | (apply exactSymbolicBinaryNullPointerRight <;> assumption)
      | (apply exactSymbolicBinaryNullPointerLeft <;> assumption)
      | (apply exactSymbolicBinary <;> assumption)
      | (apply exactSymbolicLiteralChecks <;> assumption)
      | (apply exactSymbolicSignedMinimumChecks <;> assumption)
      | (apply exactSymbolicUnaryLiteralChecks <;> assumption)
      | (apply exactSymbolicStructChecks <;> assumption)
      | (apply exactSymbolicVariantChecks <;> assumption)
      | solve_by_elim (maxDepth := 12) [
          AssociatedCallInferenceEvidence.symbolicInference,
          AssociatedCallContextualEvidence.symbolicInference,
          LiteralInfersSymbolic.default, SymbolicExprInfers.literal,
          SymbolicExprInfers.local, SymbolicExprInfers.selfValue,
          SymbolicExprInfers.constant, SymbolicExprInfers.array,
          SymbolicExprInfers.assign, SymbolicExprInfers.printI32,
          SymbolicExprInfers.assert, SymbolicExprInfers.i32ArrayDataPtr,
          SymbolicExprInfers.i32SliceFromRawParts,
          SymbolicExprInfers.i32SliceDataPtr, SymbolicExprInfers.stringDataPtr,
          SymbolicExprInfers.indexArray, SymbolicExprInfers.indexSlice,
          SymbolicExprInfers.field, SymbolicExprInfers.matchValue,
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
          SymbolicMatchArmsCheck.nil, SymbolicMatchArmsCheck.cons,
          SymbolicMatchArmsInfer.cons, SymbolicExprChecks.exact,
          SymbolicExprChecks.array, SymbolicExprChecks.scalarCast,
          SymbolicExprChecks.arrayToSlice, Static.SymbolicRequirementsGround.symbolic,
          SymbolicExprsInfer.nil, SymbolicExprsInfer.cons,
          SymbolicExprsCheck.nil, SymbolicExprsCheck.cons,
          SymbolicExprsSubstitutedCheck.nil,
          SymbolicExprsSubstitutedCheck.cons,
          SymbolicStructFieldsCheck.nil, SymbolicStructFieldsCheck.cons,
          SymbolicStructFieldsInfer.nil, SymbolicStructFieldsInfer.cons,
          SymbolicPlaceHasType.local, SymbolicPlaceHasType.selfValue,
          SymbolicPlaceHasType.field, SymbolicPlaceHasType.indexArray,
          SymbolicPlaceHasType.indexSlice]))

theorem ExprInferenceDerivationSpecializes.symbolicInference
      (specialized : ExprInferenceDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts surface symbolicType
        groundType coreExpression) :
      SymbolicExprInfers symbolic surface symbolicType := by
  deriveSymbolicProjection outer groundEnclosingReturn
    ExprInferenceDerivationSpecializes.rec

theorem ExprListInferenceDerivationSpecializes.symbolicInferences
      {outer : Static.Substitution}
      {groundEnclosingReturn : Static.GroundTy}
      {symbolic : SymbolicBodyContext}
      {concrete : SurfaceElaboration.Context}
      {contexts : symbolic.Specializes outer groundEnclosingReturn concrete}
      (specialized : ExprListInferenceDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
      groundTypes coreExpressions) :
      SymbolicExprsInfer symbolic surfaces symbolicTypes := by
    induction surfaces generalizing symbolicTypes groundTypes coreExpressions with
    | nil => cases specialized; exact .nil
    | cons surfaceHead surfaceTail induction =>
        cases specialized with
        | cons head tail =>
            exact .cons head.symbolicInference (induction tail)

theorem ExprCheckingDerivationSpecializes.symbolicCheck
      (specialized : ExprCheckingDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts surface symbolicType
        groundType coreExpression) :
      SymbolicExprChecks symbolic surface symbolicType := by
  cases specialized with
  | exact _ symbolicInferred _ _ => exact .exact symbolicInferred
  | literal lowered => exact exactSymbolicLiteralChecks lowered
  | signedMinimumLiteral lowered =>
      exact exactSymbolicSignedMinimumChecks lowered
  | unaryLiteral lowered typed =>
      exact exactSymbolicUnaryLiteralChecks lowered typed
  | array _ symbolicElements _ _ _ => exact .array symbolicElements
  | scalarCast _ symbolicInferred _ notContextualLiteral different conversion =>
      exact .scalarCast symbolicInferred notContextualLiteral different conversion
  | arrayToSlice _ symbolicInferred _ _ _ =>
      exact .arrayToSlice symbolicInferred
  | structValue selected expected arguments _ _ pathArguments requirements _ _
      symbolicFields _ =>
      exact exactSymbolicStructChecks selected expected arguments pathArguments
        requirements symbolicFields
  | variantCall selected notIntrinsic expected arguments _ _ pathArguments
      requirements _ _ symbolicPayload _ =>
      exact exactSymbolicVariantChecks selected notIntrinsic expected arguments
        pathArguments requirements symbolicPayload

theorem ExprListCheckingDerivationSpecializes.symbolicChecks
      {outer : Static.Substitution}
      {groundEnclosingReturn : Static.GroundTy}
      {symbolic : SymbolicBodyContext}
      {concrete : SurfaceElaboration.Context}
      {contexts : symbolic.Specializes outer groundEnclosingReturn concrete}
      (specialized : ExprListCheckingDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
      groundTypes coreExpressions) :
      SymbolicExprsCheck symbolic surfaces symbolicTypes := by
    induction surfaces generalizing symbolicTypes groundTypes coreExpressions with
    | nil => cases specialized; exact .nil
    | cons surfaceHead surfaceTail induction =>
        cases specialized with
        | cons head tail => exact .cons head.symbolicCheck (induction tail)

theorem ExprListSubstitutedCheckingDerivationSpecializes.symbolicSubstituted
      {outer : Static.Substitution}
      {groundEnclosingReturn : Static.GroundTy}
      {symbolic : SymbolicBodyContext}
      {concrete : SurfaceElaboration.Context}
      {contexts : symbolic.Specializes outer groundEnclosingReturn concrete}
      (inner : Static.SymbolicSubstitution)
      (specialized : ExprListSubstitutedCheckingDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts inner surfaces
      originalTypes coreExpressions) :
      SymbolicExprsSubstitutedCheck symbolic inner surfaces originalTypes := by
    induction surfaces generalizing originalTypes coreExpressions with
    | nil => cases specialized; exact .nil
    | cons surfaceHead surfaceTail induction =>
        cases specialized with
        | cons substituted head tail _ _ =>
            exact .cons substituted head.symbolicCheck (induction tail)

theorem StructFieldsCheckingDerivationSpecializes.symbolicFields
      {outer : Static.Substitution}
      {groundEnclosingReturn : Static.GroundTy}
      {symbolic : SymbolicBodyContext}
      {concrete : SurfaceElaboration.Context}
      {contexts : symbolic.Specializes outer groundEnclosingReturn concrete}
      (inner : Static.SymbolicSubstitution)
      (specialized : StructFieldsCheckingDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts inner fields
      surfaceFields coreFields) :
      SymbolicStructFieldsCheck symbolic inner fields surfaceFields := by
    induction fields generalizing surfaceFields coreFields with
    | nil => cases specialized; exact .nil
    | cons field fieldTail induction =>
        cases specialized with
        | cons removed substituted value tail _ _ =>
            exact .cons removed substituted value.symbolicCheck (induction tail)

theorem StructFieldsInferenceDerivationSpecializes.symbolicFields
      {outer : Static.Substitution}
      {groundEnclosingReturn : Static.GroundTy}
      {symbolic : SymbolicBodyContext}
      {concrete : SurfaceElaboration.Context}
      {contexts : symbolic.Specializes outer groundEnclosingReturn concrete}
      (inner : Static.SymbolicSubstitution)
      (specialized : StructFieldsInferenceDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts inner fields
      surfaceFields coreFields) :
      SymbolicStructFieldsInfer symbolic inner fields surfaceFields := by
    induction fields generalizing surfaceFields coreFields with
    | nil => cases specialized; exact .nil
    | cons field fieldTail induction =>
        cases specialized with
        | cons removed value matched tail _ _ =>
            exact .cons removed value.symbolicInference matched (induction tail)

theorem PlaceDerivationSpecializes.symbolicPlace
      {outer : Static.Substitution}
      {groundEnclosingReturn : Static.GroundTy}
      {symbolic : SymbolicBodyContext}
      {concrete : SurfaceElaboration.Context}
      {contexts : symbolic.Specializes outer groundEnclosingReturn concrete}
      (specialized : PlaceDerivationSpecializes outer groundEnclosingReturn
        symbolic concrete contexts surface symbolicType groundType corePlace) :
      SymbolicPlaceHasType symbolic surface symbolicType := by
    cases surface with
    | literal => cases specialized
    | path path =>
        cases specialized with
        | «local» single symbolicResolved _ _ =>
            exact .local single symbolicResolved
    | selfValue =>
        cases specialized with
        | selfValue symbolicResolved _ _ => exact .selfValue symbolicResolved
    | array => cases specialized
    | structValue => cases specialized
    | unary => cases specialized
    | binary => cases specialized
    | assign => cases specialized
    | call => cases specialized
    | index base index =>
        cases specialized with
        | indexArray baseProof _ _ indexProof integer =>
            exact .indexArray baseProof.symbolicPlace
              indexProof.symbolicInference integer
        | indexSlice baseProof _ indexProof integer =>
            exact .indexSlice baseProof.symbolicPlace
              indexProof.symbolicInference integer
    | member base name =>
        cases specialized with
        | field baseProof symbolicSelected _ _ =>
            exact .field baseProof.symbolicPlace symbolicSelected
    | matchValue => cases specialized
termination_by sizeOf surface

theorem MatchArmsDerivationSpecializes.symbolicArms
      {outer : Static.Substitution}
      {groundEnclosingReturn : Static.GroundTy}
      {symbolic : SymbolicBodyContext}
      {concrete : SurfaceElaboration.Context}
      {contexts : symbolic.Specializes outer groundEnclosingReturn concrete}
      (specialized : MatchArmsDerivationSpecializes outer groundEnclosingReturn
        symbolic concrete contexts next symbolicScrutinee symbolicResult
        groundScrutinee groundResult surfaceArms coreArms) :
      SymbolicMatchArmsCheck symbolic symbolicScrutinee symbolicResult
        surfaceArms := by
    induction surfaceArms generalizing coreArms with
    | nil => cases specialized; exact .nil
    | cons arm surfaceTail induction =>
        cases specialized with
        | cons pattern body tail =>
            exact .cons pattern.symbolicPattern body.symbolicCheck
              (induction tail)

theorem MatchArmsInferenceDerivationSpecializes.symbolicArms
      (specialized : MatchArmsInferenceDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts next symbolicScrutinee
        symbolicResult groundScrutinee groundResult surfaceArms coreArms) :
      SymbolicMatchArmsInfer symbolic symbolicScrutinee symbolicResult
        surfaceArms := by
    cases specialized with
    | cons pattern body tail =>
        exact .cons pattern.symbolicPattern body.symbolicInference
          tail.symbolicArms

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

theorem ExactInferenceConcreteProjection.constant
    (resolved : SurfaceElaboration.ResolvesConstant concrete path entry) :
    ExactInferenceConcreteProjection outer concrete (.path path) entry.type.toTy
      entry.type (.constant entry.constant) :=
  ⟨Static.GroundTy.toTy_instantiate entry.type outer, .constant resolved⟩

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

theorem ExactCheckingConcreteProjection.exact
    (typeGrounds : symbolicType.instantiate outer = some groundType)
    (lowered : SurfaceElaboration.ExprLowers concrete surface groundType core) :
    ExactCheckingConcreteProjection outer concrete surface symbolicType
      groundType core :=
  ⟨typeGrounds, .exact lowered⟩

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

theorem ExactInferenceConcreteProjection.i32SliceFromRawParts
    (builtin : SurfaceElaboration.builtinIntrinsic? path =
      some .i32SliceFromRawParts)
    (pointer : ExactCheckingConcreteProjection outer concrete surfacePointer
      (.scalar .rawPtr) (.scalar .rawPtr) corePointer)
    (length : ExactCheckingConcreteProjection outer concrete surfaceLength
      (.scalar (.signed .i32)) (.scalar (.signed .i32)) coreLength) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) [surfacePointer, surfaceLength])
      (.slice (.scalar (.signed .i32))) (.slice (.scalar (.signed .i32)))
      (.i32SliceFromRawParts corePointer coreLength) :=
  ⟨rfl, .i32SliceFromRawParts rfl builtin pointer.checks length.checks⟩

theorem ExactInferenceConcreteProjection.i32SliceDataPtr
    (builtin : SurfaceElaboration.builtinIntrinsic? path =
      some .i32SliceDataPtr)
    (slice : ExactCheckingConcreteProjection outer concrete surfaceSlice
      (.slice (.scalar (.signed .i32))) (.slice (.scalar (.signed .i32)))
      coreSlice) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) [surfaceSlice]) (.scalar .rawPtr) (.scalar .rawPtr)
      (.i32SliceDataPtr coreSlice) :=
  ⟨rfl, .i32SliceDataPtr rfl builtin slice.checks⟩

theorem ExactInferenceConcreteProjection.stringDataPtr
    (builtin : SurfaceElaboration.builtinIntrinsic? path = some .stringDataPtr)
    (string : ExactCheckingConcreteProjection outer concrete surfaceString
      (.scalar .string) (.scalar .string) coreString) :
    ExactInferenceConcreteProjection outer concrete
      (.call (.path path) [surfaceString]) (.scalar .rawPtr) (.scalar .rawPtr)
      (.stringDataPtr coreString) :=
  ⟨rfl, .stringDataPtr rfl builtin string.checks⟩

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

local macro "deriveConcreteProjection" outerSubstitution:ident
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
            ExactInferenceConcreteProjection.constant,
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
            ExactInferenceConcreteProjection.i32SliceFromRawParts,
            ExactInferenceConcreteProjection.i32SliceDataPtr,
            ExactInferenceConcreteProjection.stringDataPtr,
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
            concreteExprsCheckCons, concreteMatchArmsCons,
            concreteMatchArmsInferCons, concreteSubstitutedChecksCons,
            concreteStructFieldsCheckCons, concreteStructFieldsInferCons,
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
      | solve_by_elim (maxDepth := 4) [
          Eq.refl, ExactInferenceConcreteProjection.typeGrounds,
          ExactInferenceConcreteProjection.lowers,
          ExactCheckingConcreteProjection.typeGrounds,
          ExactCheckingConcreteProjection.checks,
          ExactListInferenceConcreteProjection.typeGrounds,
          ExactListInferenceConcreteProjection.lowerings,
          ExactListInferenceConcreteProjection.checks,
          ExactPlaceConcreteProjection.typeGrounds,
          ExactPlaceConcreteProjection.lowers,
          SymbolicBodyContext.Specializes.scalarCastCheck,
          Static.Ty.substitute_then_instantiate,
          Static.Ty.matchesOfInstantiate,
          Static.TySymbolicallyMatches.composeGround,
          SymbolicIntegerType.specializes,
          SymbolicAssignOpHasType.specializes,
          SurfaceElaboration.ExprLowers.local,
          SurfaceElaboration.ExprLowers.selfValue,
          SurfaceElaboration.ExprLowers.constant,
          SurfaceElaboration.ExprLowers.directCall,
          SurfaceElaboration.ExprsLower.nil,
          SurfaceElaboration.ExprsLower.cons,
          SurfaceElaboration.ExprChecks.exact,
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
  deriveConcreteProjection outer groundEnclosingReturn
    ExprInferenceDerivationSpecializes.rec

theorem ExprListInferenceDerivationSpecializes.concreteProjection
      (specialized : ExprListInferenceDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
        groundTypes coreExpressions) :
      ExactListInferenceConcreteProjection outer concrete surfaces symbolicTypes
        groundTypes coreExpressions := by
    induction surfaces generalizing symbolicTypes groundTypes coreExpressions with
    | nil => cases specialized; exact ⟨rfl, .nil, .nil⟩
    | cons surfaceHead surfaceTail induction =>
        cases specialized with
        | cons head tail => exact .cons head.concreteProjection (induction tail)

theorem ExprCheckingDerivationSpecializes.concreteProjection
      (specialized : ExprCheckingDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts surface symbolicType
        groundType coreExpression) :
      ExactCheckingConcreteProjection outer concrete surface symbolicType
        groundType coreExpression := by
  cases specialized with
  | exact _ _ typeGrounds concreteLowered =>
      exact .exact typeGrounds concreteLowered
  | literal lowered => exact .literal contexts lowered
  | signedMinimumLiteral lowered =>
      exact .signedMinimumLiteral contexts lowered
  | unaryLiteral lowered typed =>
      exact .unaryLiteral contexts lowered typed
  | array _ _ concreteElements elementGrounds elementCore =>
      exact .array concreteElements elementGrounds elementCore
  | scalarCast _ _ concreteInferred notContextualLiteral different conversion =>
      exact .scalarCast contexts concreteInferred notContextualLiteral different
        conversion
  | arrayToSlice _ _ concreteInferred elementGrounds elementCore =>
      exact .arrayToSlice concreteInferred elementGrounds elementCore
  | structValue selected expected arguments typeArgumentsGround
      constArgumentsGround pathArguments requirements artifact _ _
      concreteFields =>
      exact .structValue contexts selected expected arguments typeArgumentsGround
        constArgumentsGround pathArguments requirements artifact concreteFields
  | variantCall selected notIntrinsic expected arguments typeArgumentsGround
      constArgumentsGround pathArguments requirements artifact _ _
      concretePayload =>
      exact .variantCall contexts selected notIntrinsic expected arguments
        typeArgumentsGround constArgumentsGround pathArguments requirements
        artifact concretePayload

theorem ExprListCheckingDerivationSpecializes.concreteChecks
      (specialized : ExprListCheckingDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts surfaces symbolicTypes
        groundTypes coreExpressions) :
      SurfaceElaboration.ExprsCheck concrete surfaces groundTypes
        coreExpressions := by
    induction surfaces generalizing symbolicTypes groundTypes coreExpressions with
    | nil => cases specialized; exact .nil
    | cons surfaceHead surfaceTail induction =>
        cases specialized with
        | cons head tail =>
            exact .cons head.concreteProjection.checks (induction tail)

theorem ExprListSubstitutedCheckingDerivationSpecializes.concreteChecks
      (specialized : ExprListSubstitutedCheckingDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts inner surfaces
        originalTypes coreExpressions) :
      SurfaceElaboration.SymbolicExprsCheck concrete (inner.composeGround outer)
        surfaces originalTypes coreExpressions := by
    induction surfaces generalizing originalTypes coreExpressions with
    | nil => cases specialized; exact .nil
    | cons surfaceHead surfaceTail induction =>
        cases specialized with
        | cons substituted head tail _ _ =>
            exact concreteSubstitutedChecksCons substituted
              head.concreteProjection (induction tail)

theorem StructFieldsCheckingDerivationSpecializes.concreteFields
      (specialized : StructFieldsCheckingDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts inner fields surfaceFields
        coreFields) :
      SurfaceElaboration.StructSchemeFieldsCheck concrete
        (inner.composeGround outer) fields surfaceFields coreFields := by
    induction fields generalizing surfaceFields coreFields with
    | nil => cases specialized; exact .nil
    | cons field fieldTail induction =>
        cases specialized with
        | cons removed substituted value tail _ _ =>
            exact concreteStructFieldsCheckCons removed substituted
              value.concreteProjection (induction tail)

theorem StructFieldsInferenceDerivationSpecializes.concreteFields
      (specialized : StructFieldsInferenceDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts inner fields surfaceFields
        coreFields) :
      SurfaceElaboration.StructSchemeFieldsInfer concrete
        (inner.composeGround outer) fields surfaceFields coreFields := by
    induction fields generalizing surfaceFields coreFields with
    | nil => cases specialized; exact .nil
    | cons field fieldTail induction =>
        cases specialized with
        | cons removed value matched tail _ _ =>
            exact concreteStructFieldsInferCons removed
              value.concreteProjection matched (induction tail)

theorem PlaceDerivationSpecializes.concreteProjection
      {outer : Static.Substitution}
      {groundEnclosingReturn : Static.GroundTy}
      {symbolic : SymbolicBodyContext}
      {concrete : SurfaceElaboration.Context}
      {contexts : symbolic.Specializes outer groundEnclosingReturn concrete}
      (specialized : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
        concrete contexts surface symbolicType groundType corePlace) :
      ExactPlaceConcreteProjection outer concrete surface symbolicType groundType
        corePlace := by
    cases surface with
    | literal => cases specialized
    | path path =>
        cases specialized with
        | «local» single _ concreteResolved typeGrounds =>
            exact ⟨typeGrounds, .local _ single concreteResolved⟩
    | selfValue =>
        cases specialized with
        | selfValue _ concreteResolved typeGrounds =>
            exact ⟨typeGrounds, .selfValue concreteResolved⟩
    | array => cases specialized
    | structValue => cases specialized
    | unary => cases specialized
    | binary => cases specialized
    | assign => cases specialized
    | call => cases specialized
    | index base index =>
        cases specialized with
        | indexArray baseProof elementGrounds _ indexProof integer =>
            exact .indexArray baseProof.concreteProjection elementGrounds
              indexProof.concreteProjection integer
        | indexSlice baseProof elementGrounds indexProof integer =>
            exact .indexSlice baseProof.concreteProjection elementGrounds
              indexProof.concreteProjection integer
    | member base name =>
        cases specialized with
        | field baseProof _ concreteSelected fieldGrounds =>
            exact .field baseProof.concreteProjection concreteSelected fieldGrounds
    | matchValue => cases specialized
termination_by sizeOf surface

theorem MatchArmsDerivationSpecializes.concreteArms
      (specialized : MatchArmsDerivationSpecializes outer groundEnclosingReturn
        symbolic concrete contexts next symbolicScrutinee symbolicResult
        groundScrutinee groundResult surfaceArms coreArms) :
      SurfaceElaboration.MatchArmsLower concrete groundScrutinee groundResult
        surfaceArms coreArms := by
    induction surfaceArms generalizing coreArms with
    | nil => cases specialized; exact .nil
    | cons arm surfaceTail induction =>
        cases specialized with
        | cons pattern body tail =>
            exact concreteMatchArmsCons pattern body.concreteProjection
              (induction tail)

theorem MatchArmsInferenceDerivationSpecializes.concreteArms
      (specialized : MatchArmsInferenceDerivationSpecializes outer
        groundEnclosingReturn symbolic concrete contexts next symbolicScrutinee
        symbolicResult groundScrutinee groundResult surfaceArms coreArms) :
      SurfaceElaboration.MatchArmsInfer concrete groundScrutinee groundResult
        surfaceArms coreArms := by
    cases specialized with
    | cons pattern body tail =>
        exact concreteMatchArmsInferCons pattern body.concreteProjection
          tail.concreteArms

theorem ExprInferenceDerivationSpecializes.concreteInference
    (specialized : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface symbolicType
      groundType coreExpression) :
    symbolicType.instantiate outer = some groundType ∧
      SurfaceElaboration.ExprLowers concrete surface groundType coreExpression :=
  ⟨specialized.concreteProjection.typeGrounds,
    specialized.concreteProjection.lowers⟩

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

theorem ExprCheckingDerivationSpecializes.concreteCheck
    (specialized : ExprCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surface symbolicType
      groundType coreExpression) :
    symbolicType.instantiate outer = some groundType ∧
      SurfaceElaboration.ExprChecks concrete surface groundType coreExpression :=
  ⟨specialized.concreteProjection.typeGrounds,
    specialized.concreteProjection.checks⟩

theorem PlaceDerivationSpecializes.concretePlace
    (specialized : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surface symbolicType groundType corePlace) :
    symbolicType.instantiate outer = some groundType ∧
      SurfaceElaboration.PlaceLowers concrete surface groundType corePlace :=
  ⟨specialized.concreteProjection.typeGrounds,
    specialized.concreteProjection.lowers⟩

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

end Lanius.ProgramElaboration
