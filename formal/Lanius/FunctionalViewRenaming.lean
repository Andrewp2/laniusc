import Lanius.FunctionalViewStateful

namespace Lanius.FunctionalView

open Lanius
open Lanius.Core

/-! # Scoped environment renaming

FunctionalView fragments are often recovered with the smallest environment
that contains their live locals.  A fragment can subsequently occur inside a
larger reified command.  `Embedding` is the structural operation that places
the smaller fragment in that environment; it is also the frame boundary used
by the semantic preservation theorem below.

This is deliberately independent of parser layouts and Core variable IDs.
Those are concerns of reification.  Once a command is in FunctionalView, only
its intrinsically scoped slots remain.
-/

/-- An injective placement of one scoped environment inside another. -/
structure Embedding (source target : Nat) where
  slot : Fin source → Fin target
  injective : Function.Injective slot

/-- A duplicate-free finite slot list defines an embedding.  Keeping this
    lemma here avoids parser-specific case splits for every reified layout. -/
theorem Embedding.listGetInjective {α : Type} (values : List α)
    (nodup : values.Nodup) : Function.Injective values.get := by
  induction values with
  | nil =>
      intro left
      exact Fin.elim0 left
  | cons head tail induction =>
      have headNotMem : head ∉ tail := (List.nodup_cons.mp nodup).1
      have tailNodup : tail.Nodup := (List.nodup_cons.mp nodup).2
      have tailInjective := induction tailNodup
      intro left
      refine Fin.cases ?_ (fun leftTail => ?_) left
      · intro right
        refine Fin.cases (fun _ => rfl) (fun rightTail equal => ?_) right
        have mem := List.get_mem tail rightTail
        have same : head = tail.get rightTail := by simpa using equal
        rw [← same] at mem
        exact False.elim (headNotMem mem)
      · intro right
        refine Fin.cases (fun equal => ?_) (fun rightTail equal => ?_) right
        · have mem := List.get_mem tail leftTail
          have same : tail.get leftTail = head := by simpa using equal
          rw [same] at mem
          exact False.elim (headNotMem mem)
        · exact congrArg Fin.succ (tailInjective (by simpa using equal))

/-- Extend one slot map under a lexical binding. -/
private def Embedding.pushSlot (embedding : Embedding source target) :
    Fin (source + 1) → Fin (target + 1) := fun index =>
  if before : index.val < source then
    Fin.castSucc (embedding.slot ⟨index.val, before⟩)
  else
    Fin.last target

private theorem Embedding.pushSlot_injective
    (embedding : Embedding source target) :
    Function.Injective embedding.pushSlot := by
  intro left right equal
  apply Fin.ext
  have equalValue := congrArg Fin.val equal
  by_cases leftBefore : left.val < source
  · by_cases rightBefore : right.val < source
    · simp only [Embedding.pushSlot, leftBefore, rightBefore, ↓reduceDIte,
        Fin.val_castSucc] at equalValue
      have mapped : embedding.slot ⟨left.val, leftBefore⟩ =
          embedding.slot ⟨right.val, rightBefore⟩ := Fin.ext equalValue
      have oldEqual : (⟨left.val, leftBefore⟩ : Fin source) =
          ⟨right.val, rightBefore⟩ := embedding.injective mapped
      exact congrArg (fun index : Fin source => index.val) oldEqual
    · simp only [Embedding.pushSlot, leftBefore, rightBefore, ↓reduceDIte,
        Fin.val_castSucc, Fin.val_last] at equalValue
      have mappedLt := (embedding.slot ⟨left.val, leftBefore⟩).isLt
      omega
  · by_cases rightBefore : right.val < source
    · simp only [Embedding.pushSlot, leftBefore, rightBefore, ↓reduceDIte,
        Fin.val_castSucc, Fin.val_last] at equalValue
      have mappedLt := (embedding.slot ⟨right.val, rightBefore⟩).isLt
      omega
    · have leftLast : left.val = source := by omega
      have rightLast : right.val = source := by omega
      omega

/-- Extend an embedding under one lexical `letValue` binding.  Existing slots
    remain existing slots and the new source slot maps to the new target slot. -/
def Embedding.push (embedding : Embedding source target) :
    Embedding (source + 1) (target + 1) where
  slot := embedding.pushSlot
  injective := embedding.pushSlot_injective

@[simp] theorem Embedding.push_old (embedding : Embedding source target)
    (index : Fin source) :
    embedding.push.slot (Fin.castSucc index) =
      Fin.castSucc (embedding.slot index) := by
  simp [Embedding.push, Embedding.pushSlot, index.isLt]

@[simp] theorem Embedding.push_last (embedding : Embedding source target) :
    embedding.push.slot (Fin.last source) = Fin.last target := by
  simp [Embedding.push, Embedding.pushSlot, Fin.last]

/-- The smaller environment is the projection of the larger environment. -/
def Env.Extends (embedding : Embedding source target)
    (small : Env source) (large : Env target) : Prop :=
  ∀ index, large (embedding.slot index) = small index

/-- A finite environment is determined by its `List.ofFn` projection.  This
    is the environment analogue of layout extensionality and keeps concrete
    reified scopes from requiring one proof branch per live local. -/
theorem Env.eq_ofFn {left right : Env arity}
    (same : List.ofFn left = List.ofFn right) : left = right := by
  funext index
  have selected := congrArg (fun values => values[index.val]?) same
  have leftBound : index.val < (List.ofFn left).length := by
    simpa using index.isLt
  have rightBound : index.val < (List.ofFn right).length := by
    simpa using index.isLt
  rw [List.getElem?_eq_getElem leftBound,
    List.getElem?_eq_getElem rightBound] at selected
  simp only [Option.some.injEq] at selected
  rw [List.getElem_ofFn, List.getElem_ofFn] at selected
  simpa using selected

/-- A closed equality of finite projections establishes an environment
    embedding pointwise. -/
theorem Env.Extends.ofFn
    {embedding : Embedding source target}
    {small : Env source} {large : Env target}
    (same : List.ofFn (fun index => large (embedding.slot index)) =
      List.ofFn small) :
    Env.Extends embedding small large := by
  intro index
  have selected := congrArg (fun values => values[index.val]?) same
  have projectedBound : index.val <
      (List.ofFn (fun index => large (embedding.slot index))).length := by
    simpa using index.isLt
  have smallBound : index.val < (List.ofFn small).length := by
    simpa using index.isLt
  rw [List.getElem?_eq_getElem projectedBound,
    List.getElem?_eq_getElem smallBound] at selected
  simp only [Option.some.injEq] at selected
  rw [List.getElem_ofFn, List.getElem_ofFn] at selected
  simpa using selected

/-- A command framed by an embedding does not alter an unrelated target slot. -/
def Env.PreservesOutside (embedding : Embedding source target)
    (before after : Env target) : Prop :=
  ∀ index, (∀ sourceIndex, embedding.slot sourceIndex ≠ index) →
    after index = before index

@[simp] theorem Env.extends_refl (environment : Env arity) :
    Env.Extends ⟨id, fun _ _ => id⟩ environment environment := by
  intro index
  rfl

theorem Env.Extends.push {source target : Nat}
    {embedding : Embedding source target}
    {small : Env source} {large : Env target}
    (related : Env.Extends embedding small large)
    (value : Value) :
    Env.Extends embedding.push (small.push value) (large.push value) := by
  intro index
  refine Fin.lastCases ?_ (fun old => ?_) index
  · rw [Embedding.push_last]
    simp [Env.push]
  · rw [Embedding.push_old]
    simpa [Env.push] using related old

theorem Env.Extends.pop {source target : Nat}
    {embedding : Embedding source target}
    {small : Env (source + 1)} {large : Env (target + 1)}
    (related : Env.Extends embedding.push small large) :
    Env.Extends embedding (Stateful.Env.pop small) (Stateful.Env.pop large) := by
  intro index
  change large (Fin.castSucc (embedding.slot index)) =
    small (Fin.castSucc index)
  rw [← Embedding.push_old]
  exact related (Fin.castSucc index)

theorem Env.PreservesOutside.refl (embedding : Embedding source target)
    (environment : Env target) :
    Env.PreservesOutside embedding environment environment := by
  intro _ _
  rfl

theorem Env.PreservesOutside.trans
    (first : Env.PreservesOutside embedding before middle)
    (second : Env.PreservesOutside embedding middle after) :
    Env.PreservesOutside embedding before after := by
  intro index outside
  exact (second index outside).trans (first index outside)

/-- The values on an embedded subenvironment together with the values outside
    it determine the complete target environment.  This is the semantic frame
    rule's extensionality principle: clients can recover a canonical large
    environment without enumerating either its embedded or framed slots. -/
theorem Env.eq_of_extends_and_preserves
    {embedding : Embedding source target}
    {small : Env source} {before left right : Env target}
    (leftRelated : Env.Extends embedding small left)
    (rightRelated : Env.Extends embedding small right)
    (leftPreserved : Env.PreservesOutside embedding before left)
    (rightPreserved : Env.PreservesOutside embedding before right) :
    left = right := by
  classical
  funext index
  by_cases covered : ∃ sourceIndex, embedding.slot sourceIndex = index
  · obtain ⟨sourceIndex, rfl⟩ := covered
    exact (leftRelated sourceIndex).trans (rightRelated sourceIndex).symm
  · have outside : ∀ sourceIndex, embedding.slot sourceIndex ≠ index := by
      intro sourceIndex equal
      exact covered ⟨sourceIndex, equal⟩
    exact (leftPreserved index outside).trans
      (rightPreserved index outside).symm

theorem Env.Extends.set {source target : Nat}
    {embedding : Embedding source target}
    {small : Env source} {large : Env target}
    (related : Env.Extends embedding small large)
    (index : Fin source) (value : Value) :
    Env.Extends embedding (Stateful.Env.set small index value)
      (Stateful.Env.set large (embedding.slot index) value) := by
  intro candidate
  by_cases same : candidate = index
  · subst candidate
    simp
  · have mappedDifferent : embedding.slot candidate ≠ embedding.slot index :=
      fun equal => same (embedding.injective equal)
    simp [Stateful.Env.set, same, mappedDifferent, related candidate]

theorem Env.PreservesOutside.set
    (embedding : Embedding source target) (environment : Env target)
    (index : Fin source) (value : Value) :
    Env.PreservesOutside embedding environment
      (Stateful.Env.set environment (embedding.slot index) value) := by
  intro candidate outside
  exact Stateful.Env.set_other environment (embedding.slot index) candidate
    value (outside index).symm

theorem Env.PreservesOutside.pop
    {source target : Nat} {embedding : Embedding source target}
    {before after : Env (target + 1)}
    (preserved : Env.PreservesOutside embedding.push before after) :
    Env.PreservesOutside embedding (Stateful.Env.pop before)
      (Stateful.Env.pop after) := by
  intro index outside
  apply preserved (Fin.castSucc index)
  intro sourceIndex equal
  refine Fin.lastCases ?_ (fun sourceOld equal => ?_) sourceIndex equal
  · intro equal
    rw [Embedding.push_last] at equal
    have impossible := congrArg Fin.val equal
    change target = index.val at impossible
    omega
  · simp only [Embedding.push_old] at equal
    exact outside sourceOld (Fin.castSucc_inj.mp equal)

/-- Rename immutable references into a larger environment. -/
def Ref.rename (embedding : Embedding source target) :
    Ref source → Ref target
  | .slot index => .slot (embedding.slot index)
  | .literal value => .literal value

/-- Rename every reference in a term. -/
def Term.rename {signature : Signature} (embedding : Embedding source target) :
    Term signature source → Term signature target
  | .reference ref => .reference (ref.rename embedding)
  | .apply operation arguments =>
      .apply operation (arguments.map (Term.rename embedding))
  | .logicalAnd left right =>
      .logicalAnd (left.rename embedding) (right.rename embedding)
  | .logicalOr left right =>
      .logicalOr (left.rename embedding) (right.rename embedding)

@[simp] theorem Ref.evaluate_rename
    {source target : Nat} {embedding : Embedding source target}
    {small : Env source} {large : Env target}
    (related : Env.Extends embedding small large)
    (reference : Ref source) :
    (reference.rename embedding).evaluate large = reference.evaluate small := by
  cases reference with
  | slot index => exact related index
  | literal => rfl

theorem Term.evaluate_rename
    {signature : Signature} {source target : Nat}
    {embedding : Embedding source target}
    {small : Env source} {large : Env target}
    {machine : FunctionalView.Machine signature}
    (related : Env.Extends embedding small large)
    (term : Term signature source) :
    ∀ world,
      Term.evaluate machine world large (term.rename embedding) =
        Term.evaluate machine world small term := by
  apply @Term.rec _ _
    (fun term => ∀ world,
      Term.evaluate machine world large (term.rename embedding) =
        Term.evaluate machine world small term)
    (fun terms => ∀ world,
      evaluateTerms machine world large
          (terms.map (Term.rename embedding)) =
        evaluateTerms machine world small terms)
  · intro reference world
    cases reference with
    | slot index =>
        simp only [Term.rename, Term.evaluate, Ref.rename, Ref.evaluate]
        exact congrArg (fun value => Except.ok (value, world)) (related index)
    | literal =>
        simp only [Term.rename, Term.evaluate, Ref.rename, Ref.evaluate]
  · intro operation arguments argumentsIH world
    simp only [Term.rename, Term.evaluate]
    rw [argumentsIH world]
  · intro left right leftIH rightIH world
    simp only [Term.rename, Term.evaluate]
    rw [leftIH world]
    cases evaluated : Term.evaluate machine world small left with
    | error => rfl
    | ok result =>
        rcases result with ⟨value, afterLeft⟩
        cases value with
        | boolean boolean =>
            simp only [bind, Except.bind]
            cases boolean
            · rfl
            · exact rightIH afterLeft
        | _ => simp only [bind, Except.bind]
  · intro left right leftIH rightIH world
    simp only [Term.rename, Term.evaluate]
    rw [leftIH world]
    cases evaluated : Term.evaluate machine world small left with
    | error => rfl
    | ok result =>
        rcases result with ⟨value, afterLeft⟩
        cases value with
        | boolean boolean =>
            simp only [bind, Except.bind]
            cases boolean
            · exact rightIH afterLeft
            · rfl
        | _ => simp only [bind, Except.bind]
  · intro world
    rfl
  · intro head tail headIH tailIH world
    simp only [List.map_cons, evaluateTerms]
    rw [headIH world]
    cases evaluated : Term.evaluate machine world small head with
    | error => rfl
    | ok result =>
        rcases result with ⟨value, afterHead⟩
        simp only [bind, Except.bind]
        rw [tailIH afterHead]

namespace Stateful

/-- Actions are intrinsically scoped too, so a command dialect supplies its
    structural action renaming once. -/
structure ActionRenamer {signature : Signature}
    (actions : ActionSignature signature) where
  rename : {source target : Nat} → Embedding source target →
    actions.Action source → actions.Action target

/-- Rename a stateful command, lifting the embedding beneath lexical lets. -/
def Command.rename {signature : Signature}
    {actions : ActionSignature signature} (renamer : ActionRenamer actions)
    (embedding : Embedding source target) :
    Command signature actions source → Command signature actions target
  | .skip => .skip
  | .sequence first second =>
      .sequence (first.rename renamer embedding) (second.rename renamer embedding)
  | .letValue type initializer body =>
      .letValue type (initializer.rename embedding)
        (body.rename renamer embedding.push)
  | .setLocal index value =>
      .setLocal (embedding.slot index) (value.rename embedding)
  | .updateLocal operation index value =>
      .updateLocal operation (embedding.slot index) (value.rename embedding)
  | .action operation => .action (renamer.rename embedding operation)
  | .ifThenElse condition thenBranch elseBranch =>
      .ifThenElse (condition.rename embedding)
        (thenBranch.rename renamer embedding)
        (elseBranch.rename renamer embedding)
  | .whileLoop condition body =>
      .whileLoop (condition.rename embedding) (body.rename renamer embedding)
  | .returnValue value => .returnValue (value.map (Term.rename embedding))
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

/-- Semantic naturality required of a dialect's action renaming. -/
def ActionRenamer.Sound {signature : Signature}
    {actions : ActionSignature signature} (renamer : ActionRenamer actions)
    (termMachine : FunctionalView.Machine signature)
    (machine : Machine termMachine actions) : Prop :=
  ∀ {source target : Nat} (embedding : Embedding source target)
    (world : termMachine.World) (small : Env source) (large : Env target)
    (related : Env.Extends embedding small large)
    (action : actions.Action source),
    machine.evalAction world large (renamer.rename embedding action) =
      machine.evalAction world small action

/-- A renamed command has exactly the source command's behavior on embedded
    locals and leaves every other target local untouched.  This is the frame
    theorem that permits a proved compiler fragment to be reused inside a
    larger mechanically reified environment. -/
theorem Command.Evaluates.rename
    {signature : Signature} {actions : ActionSignature signature}
    {termMachine : FunctionalView.Machine signature}
    {machine : Machine termMachine actions}
    {renamer : ActionRenamer actions}
    {arity : Nat} {beforeWorld afterWorld : termMachine.World}
    {beforeSmall afterSmall : Env arity}
    {command : Command signature actions arity}
    {completion : Completion}
    (renamerSound : renamer.Sound termMachine machine)
    (evaluated : Command.Evaluates termMachine machine beforeWorld
      beforeSmall command completion afterWorld afterSmall) :
    ∀ {target : Nat} (embedding : Embedding arity target)
      (beforeLarge : Env target),
      Env.Extends embedding beforeSmall beforeLarge →
      ∃ afterLarge,
        Command.Evaluates termMachine machine beforeWorld beforeLarge
          (command.rename renamer embedding) completion afterWorld afterLarge ∧
        Env.Extends embedding afterSmall afterLarge ∧
        Env.PreservesOutside embedding beforeLarge afterLarge := by
  induction evaluated with
  | skip =>
      intro target embedding beforeLarge related
      exact ⟨beforeLarge, .skip, related,
        Env.PreservesOutside.refl embedding beforeLarge⟩
  | sequenceNext firstResult secondResult firstIH secondIH =>
      intro target embedding beforeLarge related
      obtain ⟨middleLarge, firstRenamed, middleRelated, firstPreserved⟩ :=
        firstIH embedding beforeLarge related
      obtain ⟨afterLarge, secondRenamed, afterRelated, secondPreserved⟩ :=
        secondIH embedding middleLarge middleRelated
      exact ⟨afterLarge, .sequenceNext firstRenamed secondRenamed,
        afterRelated, firstPreserved.trans secondPreserved⟩
  | sequenceStop firstResult stops firstIH =>
      intro target embedding beforeLarge related
      obtain ⟨afterLarge, firstRenamed, afterRelated, preserved⟩ :=
        firstIH embedding beforeLarge related
      exact ⟨afterLarge, .sequenceStop firstRenamed stops,
        afterRelated, preserved⟩
  | letValue =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall initializer value
        initializedWorld body sourceCompletion sourceAfterWorld
        extendedEnvironment type initializerResult bodyResult bodyIH
      intro target embedding beforeLarge related
      have renamedInitializer :
          Term.evaluate termMachine sourceBeforeWorld beforeLarge
              (initializer.rename embedding) =
            .ok (value, initializedWorld) := by
        rw [Term.evaluate_rename related initializer]
        exact initializerResult
      obtain ⟨extendedLarge, renamedBody, extendedRelated,
        extendedPreserved⟩ :=
        bodyIH embedding.push (beforeLarge.push value) (related.push value)
      let afterLarge := Stateful.Env.pop extendedLarge
      have afterRelated : Env.Extends embedding
          (Stateful.Env.pop extendedEnvironment) afterLarge :=
        extendedRelated.pop
      have preservedFromPushed : Env.PreservesOutside embedding
          (Stateful.Env.pop (beforeLarge.push value)) afterLarge :=
        extendedPreserved.pop
      have poppedBefore : Stateful.Env.pop (beforeLarge.push value) =
          beforeLarge := Stateful.Env.pop_push beforeLarge value
      rw [poppedBefore] at preservedFromPushed
      exact ⟨afterLarge, .letValue renamedInitializer renamedBody,
        afterRelated, preservedFromPushed⟩
  | setLocal =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall value result
        sourceAfterWorld slot valueResult
      intro target embedding beforeLarge related
      have renamedValue : Term.evaluate termMachine sourceBeforeWorld beforeLarge
          (value.rename embedding) = .ok (result, sourceAfterWorld) := by
        rw [Term.evaluate_rename related value]
        exact valueResult
      exact ⟨Stateful.Env.set beforeLarge (embedding.slot slot) result,
        .setLocal renamedValue, related.set slot result,
        Env.PreservesOutside.set embedding beforeLarge slot result⟩
  | updateLocal =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall value right
        sourceAfterWorld operation slot result valueResult updateResult
      intro targetArity embedding beforeLarge related
      have renamedValue : Term.evaluate termMachine sourceBeforeWorld beforeLarge
          (value.rename embedding) = .ok (right, sourceAfterWorld) := by
        rw [Term.evaluate_rename related value]
        exact valueResult
      have renamedUpdate : machine.evalLocalUpdate operation
          (beforeLarge (embedding.slot slot)) right = .ok result := by
        rw [related slot]
        exact updateResult
      exact ⟨Stateful.Env.set beforeLarge (embedding.slot slot) result,
        .updateLocal renamedValue renamedUpdate, related.set slot result,
        Env.PreservesOutside.set embedding beforeLarge slot result⟩
  | action =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall operation
        sourceAfterWorld actionResult
      intro target embedding beforeLarge related
      have renamedAction : machine.evalAction sourceBeforeWorld beforeLarge
          (renamer.rename embedding operation) = .ok sourceAfterWorld := by
        rw [renamerSound embedding sourceBeforeWorld sourceBeforeSmall
          beforeLarge related operation]
        exact actionResult
      exact ⟨beforeLarge, .action renamedAction, related,
        Env.PreservesOutside.refl embedding beforeLarge⟩
  | ifTrue =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall condition
        conditionWorld thenBranch sourceCompletion sourceAfterWorld
        sourceAfterEnvironment elseBranch conditionResult branchResult branchIH
      intro target embedding beforeLarge related
      have renamedCondition : Term.evaluate termMachine sourceBeforeWorld beforeLarge
          (condition.rename embedding) =
          .ok (.boolean true, conditionWorld) := by
        rw [Term.evaluate_rename related condition]
        exact conditionResult
      obtain ⟨afterLarge, renamedBranch, afterRelated, preserved⟩ :=
        branchIH embedding beforeLarge related
      exact ⟨afterLarge, .ifTrue renamedCondition renamedBranch,
        afterRelated, preserved⟩
  | ifFalse =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall condition
        conditionWorld elseBranch sourceCompletion sourceAfterWorld
        sourceAfterEnvironment thenBranch conditionResult branchResult branchIH
      intro target embedding beforeLarge related
      have renamedCondition : Term.evaluate termMachine sourceBeforeWorld beforeLarge
          (condition.rename embedding) =
          .ok (.boolean false, conditionWorld) := by
        rw [Term.evaluate_rename related condition]
        exact conditionResult
      obtain ⟨afterLarge, renamedBranch, afterRelated, preserved⟩ :=
        branchIH embedding beforeLarge related
      exact ⟨afterLarge, .ifFalse renamedCondition renamedBranch,
        afterRelated, preserved⟩
  | whileFalse =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall condition
        sourceAfterWorld body conditionResult
      intro target embedding beforeLarge related
      have renamedCondition : Term.evaluate termMachine sourceBeforeWorld beforeLarge
          (condition.rename embedding) =
          .ok (.boolean false, sourceAfterWorld) := by
        rw [Term.evaluate_rename related condition]
        exact conditionResult
      exact ⟨beforeLarge, .whileFalse renamedCondition, related,
        Env.PreservesOutside.refl embedding beforeLarge⟩
  | whileNext =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall condition
        conditionWorld body bodyWorld bodyEnvironment sourceCompletion
        sourceAfterWorld sourceAfterEnvironment conditionResult bodyResult
        restResult bodyIH restIH
      intro target embedding beforeLarge related
      have renamedCondition : Term.evaluate termMachine sourceBeforeWorld beforeLarge
          (condition.rename embedding) =
          .ok (.boolean true, conditionWorld) := by
        rw [Term.evaluate_rename related condition]
        exact conditionResult
      obtain ⟨bodyLarge, renamedBody, bodyRelated, bodyPreserved⟩ :=
        bodyIH embedding beforeLarge related
      obtain ⟨afterLarge, renamedRest, afterRelated, restPreserved⟩ :=
        restIH embedding bodyLarge bodyRelated
      exact ⟨afterLarge,
        .whileNext renamedCondition renamedBody renamedRest,
        afterRelated, bodyPreserved.trans restPreserved⟩
  | whileContinue =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall condition
        conditionWorld body bodyWorld bodyEnvironment sourceCompletion
        sourceAfterWorld sourceAfterEnvironment conditionResult bodyResult
        restResult bodyIH restIH
      intro target embedding beforeLarge related
      have renamedCondition : Term.evaluate termMachine sourceBeforeWorld beforeLarge
          (condition.rename embedding) =
          .ok (.boolean true, conditionWorld) := by
        rw [Term.evaluate_rename related condition]
        exact conditionResult
      obtain ⟨bodyLarge, renamedBody, bodyRelated, bodyPreserved⟩ :=
        bodyIH embedding beforeLarge related
      obtain ⟨afterLarge, renamedRest, afterRelated, restPreserved⟩ :=
        restIH embedding bodyLarge bodyRelated
      exact ⟨afterLarge,
        .whileContinue renamedCondition renamedBody renamedRest,
        afterRelated, bodyPreserved.trans restPreserved⟩
  | whileBreak =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall condition
        conditionWorld body sourceAfterWorld sourceAfterEnvironment
        conditionResult bodyResult bodyIH
      intro target embedding beforeLarge related
      have renamedCondition : Term.evaluate termMachine sourceBeforeWorld beforeLarge
          (condition.rename embedding) =
          .ok (.boolean true, conditionWorld) := by
        rw [Term.evaluate_rename related condition]
        exact conditionResult
      obtain ⟨afterLarge, renamedBody, afterRelated, preserved⟩ :=
        bodyIH embedding beforeLarge related
      exact ⟨afterLarge, .whileBreak renamedCondition renamedBody,
        afterRelated, preserved⟩
  | whileReturn =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall condition
        conditionWorld body returnedValue sourceAfterWorld sourceAfterEnvironment
        conditionResult bodyResult bodyIH
      intro target embedding beforeLarge related
      have renamedCondition : Term.evaluate termMachine sourceBeforeWorld beforeLarge
          (condition.rename embedding) =
          .ok (.boolean true, conditionWorld) := by
        rw [Term.evaluate_rename related condition]
        exact conditionResult
      obtain ⟨afterLarge, renamedBody, afterRelated, preserved⟩ :=
        bodyIH embedding beforeLarge related
      exact ⟨afterLarge, .whileReturn renamedCondition renamedBody,
        afterRelated, preserved⟩
  | returnNone =>
      intro target embedding beforeLarge related
      exact ⟨beforeLarge, .returnNone, related,
        Env.PreservesOutside.refl embedding beforeLarge⟩
  | returnSome =>
      rename_i sourceBeforeWorld sourceArity sourceBeforeSmall value result
        sourceAfterWorld valueResult
      intro target embedding beforeLarge related
      have renamedValue : Term.evaluate termMachine sourceBeforeWorld beforeLarge
          (value.rename embedding) = .ok (result, sourceAfterWorld) := by
        rw [Term.evaluate_rename related value]
        exact valueResult
      exact ⟨beforeLarge, .returnSome renamedValue, related,
        Env.PreservesOutside.refl embedding beforeLarge⟩
  | breakLoop =>
      intro target embedding beforeLarge related
      exact ⟨beforeLarge, .breakLoop, related,
        Env.PreservesOutside.refl embedding beforeLarge⟩
  | continueLoop =>
      intro target embedding beforeLarge related
      exact ⟨beforeLarge, .continueLoop, related,
        Env.PreservesOutside.refl embedding beforeLarge⟩

/-- Typed result of executing a renamed command in a larger environment.
    The semantic theorem naturally hides the target post-environment behind
    an existential; compiler proofs generally need to pass that environment to
    the next command, so this record provides the single canonical elimination
    point instead of repeating `Classical.choose` in every client. -/
structure Command.RenameResult
    {signature : Signature} {actions : ActionSignature signature}
    {termMachine : FunctionalView.Machine signature}
    (machine : Machine termMachine actions) (renamer : ActionRenamer actions)
    {arity target : Nat} (embedding : Embedding arity target)
    (beforeWorld : termMachine.World) (beforeLarge : Env target)
    (command : Command signature actions arity) (completion : Completion)
    (afterWorld : termMachine.World) (afterSmall : Env arity) : Type where
  afterLarge : Env target
  evaluated : Command.Evaluates termMachine machine beforeWorld beforeLarge
    (command.rename renamer embedding) completion afterWorld afterLarge
  related : Env.Extends embedding afterSmall afterLarge
  preserved : Env.PreservesOutside embedding beforeLarge afterLarge

/-- Package the frame theorem's existential target environment as reusable
    computational proof data. -/
noncomputable def Command.Evaluates.renameResult
    {signature : Signature} {actions : ActionSignature signature}
    {termMachine : FunctionalView.Machine signature}
    {machine : Machine termMachine actions}
    {renamer : ActionRenamer actions}
    {arity target : Nat} {beforeWorld afterWorld : termMachine.World}
    {beforeSmall afterSmall : Env arity}
    {command : Command signature actions arity}
    {completion : Completion}
    (renamerSound : renamer.Sound termMachine machine)
    (evaluated : Command.Evaluates termMachine machine beforeWorld beforeSmall
      command completion afterWorld afterSmall)
    (embedding : Embedding arity target) (beforeLarge : Env target)
    (related : Env.Extends embedding beforeSmall beforeLarge) :
    Command.RenameResult machine renamer embedding beforeWorld beforeLarge command
      completion afterWorld afterSmall := by
  let existsResult := evaluated.rename renamerSound embedding beforeLarge related
  let afterLarge := Classical.choose existsResult
  have specification := Classical.choose_spec existsResult
  exact {
    afterLarge := afterLarge
    evaluated := specification.1
    related := specification.2.1
    preserved := specification.2.2
  }

end Stateful

end Lanius.FunctionalView
