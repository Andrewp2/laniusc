import Lanius.Compiler.SignatureCheck

namespace Lanius.Compiler.FunctionContextCheck

open Lanius
open Lanius.Compiler.ProgramLowering

inductive ParameterBindingsMatch (monomorphization : Static.Monomorphization) :
    List SurfaceElaboration.LocalBinding → List (VarId × Core.Ty) → Prop where
  | nil : ParameterBindingsMatch monomorphization [] []
  | cons (name : Surface.Name) (id : VarId) (ground : Static.GroundTy)
      (core : Core.Ty)
      (grounded : ground.toCore monomorphization = some core)
      (tail : ParameterBindingsMatch monomorphization tailBindings tailParameters) :
      ParameterBindingsMatch
        monomorphization
        ({ name := name, id := id, type := ground } :: tailBindings)
        ((id, core) :: tailParameters)

private theorem parameterContext_lookup_nodup
    (parameters : List (VarId × Core.Ty))
    (unique : (parameters.map Prod.fst).Nodup) (id : VarId) :
    Typing.parameterContext parameters id =
      (parameters.find? (fun parameter => parameter.1 == id)).map Prod.snd := by
  induction parameters with
  | nil => simp [Typing.parameterContext, Typing.Context.empty]
  | cons head tail ih =>
      have split : head.1 ∉ tail.map Prod.fst ∧ (tail.map Prod.fst).Nodup := by
        simpa only [List.map_cons] using (List.nodup_cons.mp unique)
      simp only [Typing.parameterContext, List.foldl_cons, Typing.Context.bind]
      by_cases same : head.1 = id
      · subst id
        rw [List.find?_cons]
        simp
        change List.foldl (fun result binding => result.bind binding.1 binding.2)
          (Typing.Context.empty.bind head.1 head.2) tail head.1 =
          some head.2
        have preserve : ∀ (items : List (VarId × Core.Ty))
            (context : Typing.Context), head.1 ∉ items.map Prod.fst →
            List.foldl (fun result binding => result.bind binding.1 binding.2)
              context items head.1 = context head.1 := by
          intro items
          induction items with
          | nil => intro context _; rfl
          | cons next rest tailIH =>
              intro context noItems
              simp only [List.foldl_cons]
              rw [tailIH]
              · simp [List.mem_map] at noItems
                rcases noItems with ⟨notNext, noRest⟩
                simp [Typing.Context.bind, notNext]
              · intro member
                exact noItems (by simp [member])
        rw [preserve tail (Typing.Context.empty.bind head.1 head.2)]
        · simp [Typing.Context.bind]
        · intro member
          exact split.1 member
      · have independent : ∀ (items : List (VarId × Core.Ty))
            (context : Typing.Context) (headId : VarId) (headType : Core.Ty),
            headId ∉ items.map Prod.fst → headId ≠ id →
            List.foldl (fun result binding => result.bind binding.1 binding.2)
              (context.bind headId headType) items id =
              List.foldl (fun result binding => result.bind binding.1 binding.2)
                context items id := by
          intro items
          induction items with
          | nil =>
              intro context headId headType _ different
              simp [Typing.Context.bind, different, Ne.symm different]
          | cons next rest tailIH =>
              intro context headId headType noItems different
              simp only [List.foldl_cons]
              have headDifferent : headId ≠ next.1 := by
                intro equal
                apply noItems
                exact List.mem_map.mpr ⟨next, List.mem_cons_self, equal.symm⟩
              have noRest : headId ∉ rest.map Prod.fst := by
                intro member
                apply noItems
                rcases List.mem_map.mp member with ⟨item, itemMem, itemEq⟩
                exact List.mem_map.mpr ⟨item, List.mem_cons_of_mem _ itemMem, itemEq⟩
              have commute :
                  (context.bind headId headType).bind next.1 next.2 =
                    (context.bind next.1 next.2).bind headId headType := by
                funext query
                by_cases hHead : query = headId
                · subst query
                  simp [Typing.Context.bind, headDifferent, Ne.symm headDifferent]
                · by_cases hNext : query = next.1
                  · subst query
                    simp [Typing.Context.bind, headDifferent, Ne.symm headDifferent]
                  · simp [Typing.Context.bind, hHead, hNext]
              rw [commute]
              exact tailIH (context := context.bind next.1 next.2)
                (headId := headId) (headType := headType) noRest different
        have sameBool : (head.1 == id) = false := by simp [same]
        rw [List.find?_cons, sameBool]
        rw [independent tail Typing.Context.empty head.1 head.2]
        · exact ih split.2
        · exact split.1
        · exact same

private theorem localLookup_eq_of_match
    (monomorphization : Static.Monomorphization)
    (matched : ParameterBindingsMatch monomorphization bindings parameters) (query : VarId) :
    (bindings.find? (fun binding => binding.id == query)).bind
        (fun binding => binding.type.toCore monomorphization) =
      (parameters.find? (fun parameter => parameter.1 == query)).map Prod.snd := by
  induction matched with
  | nil => rfl
  | cons name id ground core grounded tail ih =>
      simp only [List.find?_cons]
      by_cases same : id == query
      · simp [same]
        exact grounded
      · simp [same, ih]

private theorem coreLocals_eq_of_match
    (context : SurfaceElaboration.Context)
    (matched : ParameterBindingsMatch context.monomorphization bindings parameters)
    (unique : (parameters.map Prod.fst).Nodup)
    (locals : context.locals = bindings) :
    context.coreLocals = Typing.parameterContext parameters := by
  funext query
  rw [parameterContext_lookup_nodup parameters unique query]
  change (context.locals.find? (fun binding => binding.id == query)).bind
      (fun binding => binding.type.toCore context.monomorphization) = _
  rw [locals]
  exact localLookup_eq_of_match context.monomorphization matched query

def buildParameters :
    (context : SurfaceElaboration.Context) →
    (surface : List Surface.Parameter) →
    (core : List (VarId × Core.Ty)) →
    Option { bindings : List SurfaceElaboration.LocalBinding //
      ParameterBindingsMatch context.monomorphization bindings core }
  | _, [], [] => some ⟨[], .nil⟩
  | context, .named name surfaceType :: surfaceTail, (id, coreType) :: coreTail =>
      match TypeLoweringCheck.check context surfaceType coreType with
      | none => none
      | some typed =>
          match buildParameters context surfaceTail coreTail with
          | none => none
          | some ⟨bindings, matched⟩ =>
              some ⟨{ name, id, type := typed.groundType } :: bindings,
                .cons name id typed.groundType coreType typed.grounded matched⟩
  | _, _, _ => none

inductive Failure where
  | unsupportedParameters
  | unsupportedDeclaration
  | duplicateParameter
  | signature (failure : SignatureCheck.Failure)
deriving DecidableEq, Repr

structure Checked
    (base : SurfaceElaboration.Context) (moduleId : ModuleId)
    (surfaceParameters : List Surface.Parameter)
    (surfaceReturn : Option Surface.TypeExpr)
    (core : Core.Function) where
  context : SurfaceElaboration.Context
  next : VarId
  signature : SignatureCheck.CheckedSignature context surfaceParameters
    surfaceReturn core.parameters core.returnType
  parameterMatch : ParameterBindingsMatch context.monomorphization context.locals core.parameters
  contextMatches : ContextMatches context base base.names moduleId
  parameterContext : context.coreLocals = Typing.parameterContext core.parameters
  nextCanonical : next = context.nextExpressionLocalId
  nextFresh : SurfaceElaboration.FreshLocalId context next

def check
    (base : SurfaceElaboration.Context) (moduleId : ModuleId)
    (surfaceParameters : List Surface.Parameter)
    (surfaceReturn : Option Surface.TypeExpr) (core : Core.Function) :
    Except Failure (Checked base moduleId surfaceParameters surfaceReturn core) :=
  if unique : (core.parameters.map Prod.fst).Nodup then
    let moduleContext := base.forModule moduleId
    match buildParameters moduleContext surfaceParameters core.parameters with
    | none => .error .unsupportedParameters
    | some ⟨bindings, parameterMatch⟩ =>
        let context : SurfaceElaboration.Context :=
          { moduleContext with locals := bindings }
        have contextLocals : context.locals = bindings := rfl
        match signature : SignatureCheck.check context surfaceParameters
            surfaceReturn core.parameters core.returnType with
        | .error failure => .error (.signature failure)
        | .ok checkedSignature =>
            let next := context.nextExpressionLocalId
            .ok {
              context := context
              next := next
              signature := checkedSignature
              parameterMatch := by simpa [context] using parameterMatch
              contextMatches := by
                simp only [ContextMatches, context]
                exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
              parameterContext := coreLocals_eq_of_match context parameterMatch unique
                contextLocals
              nextCanonical := rfl
              nextFresh := SurfaceElaboration.LocalIdsBelow.fresh
                (SurfaceElaboration.Context.localIdsBelow_nextExpressionLocalId context) }
  else .error .duplicateParameter

def checkFunction (base : SurfaceElaboration.Context) (moduleId : ModuleId)
    (declaration : Surface.Function) (core : Core.Function) :=
  match declaration.genericParameters, declaration.wherePredicates with
  | [], [] => check base moduleId declaration.parameters declaration.returnType core
  | _, _ => .error .unsupportedDeclaration

def checkExternFunction (base : SurfaceElaboration.Context) (moduleId : ModuleId)
    (declaration : Surface.ExternFunction) (core : Core.Function) :=
  match declaration.abi, declaration.genericParameters, declaration.wherePredicates with
  | none, [], [] => check base moduleId declaration.parameters declaration.returnType core
  | _, _, _ => .error .unsupportedDeclaration

end Lanius.Compiler.FunctionContextCheck
