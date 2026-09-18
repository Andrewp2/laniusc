import Lanius.Extraction.CanonicalTokens.KeywordDecision5
import Lanius.Extraction.CanonicalTokens.KeywordDecision6
import Lanius.Extraction.CanonicalTokens.KeywordDecision8
import Lanius.Extraction.CanonicalTokens.KeywordChoice

namespace Lanius.Extraction.CanonicalTokens.KeywordDispatchSemantics

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens

abbrev TM := KeywordSemantics.TM
abbrev SM := KeywordSemantics.SM

def branchCommands : List (Nat × KeywordCommand.C 4) := [
  (2, KeywordCommand.directLoad2
    (KeywordCommand.directChoices KeywordCommand.length2Rules)),
  (3, KeywordCommand.directLoad3
    (KeywordCommand.directChoices KeywordCommand.length3Rules)),
  (4, KeywordCommand.directLoad4
    (KeywordCommand.directChoices KeywordCommand.length4Rules)),
  (5, KeywordCommand.directLoad5
    (KeywordCommand.directChoices KeywordCommand.length5Rules)),
  (6, KeywordCommand.directLoad6
    (KeywordCommand.directChoices KeywordCommand.length6Rules)),
  (8, KeywordCommand.directLoad8
    (KeywordCommand.directChoices KeywordCommand.length8Rules))]

def branchSequence : List (Nat × KeywordCommand.C 4) → KeywordCommand.C 4
  | [] => KeywordCommand.directReturned (KeywordCommand.directConstant 7)
  | (length, command) :: rest =>
      .sequence (KeywordCommand.directLengthBranch length command)
        (branchSequence rest)

def body : KeywordCommand.C 4 := branchSequence branchCommands

theorem directCommand_body : KeywordCommand.directCommand =
    .letValue KeywordCommand.i32
      (KeywordCommand.directBinary .subtract (KeywordCommand.directSlot 2)
        (KeywordCommand.directSlot 1) KeywordCommand.i32) body := by
  rfl

@[simp] theorem lengthEnvironment_last
    (cell : CellId) (leading spelling trailing : List Int) :
    KeywordSemantics.lengthEnvironment cell leading spelling trailing
      ⟨3, by decide⟩ = .signed .i32 (Int.ofNat spelling.length) := by
  unfold KeywordSemantics.lengthEnvironment
  rw [Env.push_last]

theorem lengthCondition_evaluates
    (cell : CellId) (leading spelling trailing : List Int) (expected : Int) :
    Term.evaluate TM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading spelling trailing)
      (KeywordCommand.directEqual (KeywordCommand.directSlot 3)
        (KeywordCommand.directLiteral expected)) =
    .ok (.boolean (Int.ofNat spelling.length == expected),
      Model.keywordWorld cell (leading ++ spelling ++ trailing)) := by
  apply KeywordLengthSemantics.directEqual_evaluates
    (environment := KeywordSemantics.lengthEnvironment cell leading spelling trailing)
    (position := ⟨3, by decide⟩)
    (actual := Int.ofNat spelling.length)
    (expected := expected)
  exact lengthEnvironment_last cell leading spelling trailing

theorem lengthBranch_false
    (cell : CellId) (leading spelling trailing : List Int) (expected : Int)
    (body : KeywordCommand.C 4)
    (different : (Int.ofNat spelling.length == expected) = false) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading spelling trailing)
      (KeywordCommand.directLengthBranch expected body) =
    some (.next, Model.keywordWorld cell (leading ++ spelling ++ trailing),
      KeywordSemantics.lengthEnvironment cell leading spelling trailing) := by
  have condition := lengthCondition_evaluates cell leading spelling trailing expected
  rw [different] at condition
  unfold KeywordCommand.directLengthBranch
  simp only [Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [condition]

theorem lengthBranch_true
    (cell : CellId) (leading spelling trailing : List Int) (expected : Int)
    (body : KeywordCommand.C 4) (completion : Stateful.Completion)
    (same : (Int.ofNat spelling.length == expected) = true)
    (bodyResult :
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld cell (leading ++ spelling ++ trailing))
        (KeywordSemantics.lengthEnvironment cell leading spelling trailing) body =
      some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
        KeywordSemantics.lengthEnvironment cell leading spelling trailing)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading spelling trailing)
      (KeywordCommand.directLengthBranch expected body) =
    some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
      KeywordSemantics.lengthEnvironment cell leading spelling trailing) := by
  have condition := lengthCondition_evaluates cell leading spelling trailing expected
  rw [same] at condition
  unfold KeywordCommand.directLengthBranch
  simp only [Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [condition]
  exact bodyResult

theorem sequence_next
    (world : World) (environment : Env arity)
    (first second : Stateful.Command Core.signature actions arity)
    (completion : Stateful.Completion)
    (firstResult :
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world environment first =
        some (.next, world, environment))
    (secondResult :
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world environment second =
      some (completion, world, environment)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world environment
        (.sequence first second) = some (completion, world, environment) := by
  simp only [Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [firstResult]
  exact secondResult

theorem sequence_stop
    (world : World) (environment : Env arity)
    (first second : Stateful.Command Core.signature actions arity)
    (value : Option Value)
    (firstResult :
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world environment first =
        some (.returned value, world, environment)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world environment
        (.sequence first second) =
      some (.returned value, world, environment) := by
  simp only [Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [firstResult]

theorem identifier_return_evaluates
    (cell : CellId) (leading spelling trailing : List Int) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading spelling trailing)
      (KeywordCommand.directReturned (KeywordCommand.directConstant 7)) =
    some (.returned
      (some (.signed .i32 (Int.ofNat Compiler.TokenKind.identifier.gpuCode))),
      Model.keywordWorld cell (leading ++ spelling ++ trailing),
      KeywordSemantics.lengthEnvironment cell leading spelling trailing) := by
  have constant : verifiedFrontendCore.constant? 7 = some {
      id := 7, type := KeywordCommand.i32,
      value := .signed .i32 (Int.ofNat Compiler.TokenKind.identifier.gpuCode) } := by
    rfl
  have evaluated := KeywordLengthSemantics.directConstant_evaluates
    (world := Model.keywordWorld cell (leading ++ spelling ++ trailing))
    (environment := KeywordSemantics.lengthEnvironment cell leading spelling trailing)
    (constant := 7) _ constant
  unfold KeywordCommand.directReturned
  simp only [Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [evaluated]

private theorem branchSequence_evaluates
    (branches : List (Nat × KeywordCommand.C 4))
    (cell : CellId) (leading spelling trailing : List Int) (expected : Value)
    (outcome : ∀ width command, (width, command) ∈ branches →
      spelling.length = width →
      KeywordChoice.Outcome
        (Model.keywordWorld cell (leading ++ spelling ++ trailing))
        (KeywordSemantics.lengthEnvironment cell leading spelling trailing)
        expected command)
    (covered : spelling.length ∈ branches.map Prod.fst ∨
      expected = .signed .i32 (Int.ofNat Compiler.TokenKind.identifier.gpuCode)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading spelling trailing)
      (branchSequence branches) =
    some (.returned (some expected), Model.keywordWorld cell (leading ++ spelling ++ trailing),
      KeywordSemantics.lengthEnvironment cell leading spelling trailing) := by
  induction branches with
  | nil =>
      rcases covered with impossible | expectedIdentifier
      · simp at impossible
      · subst expected
        simpa [branchSequence] using
          (identifier_return_evaluates cell leading spelling trailing)
  | cons head tail inductionHypothesis =>
      obtain ⟨width, command⟩ := head
      have tailOutcome : ∀ nextWidth nextCommand,
          (nextWidth, nextCommand) ∈ tail → spelling.length = nextWidth →
          KeywordChoice.Outcome
            (Model.keywordWorld cell (leading ++ spelling ++ trailing))
            (KeywordSemantics.lengthEnvironment cell leading spelling trailing)
            expected nextCommand := by
        intro nextWidth nextCommand member sameLength
        exact outcome nextWidth nextCommand
          (List.mem_cons_of_mem _ member) sameLength
      by_cases same : spelling.length = width
      · have sameBeq : (Int.ofNat spelling.length == Int.ofNat width) = true := by
          simp [same]
        have headOutcome := outcome width command (by simp) same
        rcases headOutcome with returned | next
        · have branch := lengthBranch_true cell leading spelling trailing width command
            (.returned (some expected)) sameBeq returned
          exact sequence_stop _ _ _ _ (some expected) branch
        · rcases next with ⟨expectedIdentifier, nextResult⟩
          have tailResult := inductionHypothesis tailOutcome
            (Or.inr expectedIdentifier)
          have branch := lengthBranch_true cell leading spelling trailing width command
            .next sameBeq nextResult
          exact sequence_next _ _ _ _ _ branch tailResult
      · have different : (Int.ofNat spelling.length == Int.ofNat width) = false := by
          apply beq_eq_false_iff_ne.mpr
          intro sameLength
          exact same (Int.ofNat_inj.mp sameLength)
        have tailCovered : spelling.length ∈ tail.map Prod.fst ∨
            expected = .signed .i32 (Int.ofNat Compiler.TokenKind.identifier.gpuCode) := by
          rcases covered with member | expectedIdentifier
          · simp only [List.map_cons, List.mem_cons] at member
            rcases member with sameLength | member
            · exact False.elim (same (by simpa using sameLength))
            · exact Or.inl member
          · exact Or.inr expectedIdentifier
        have branch := lengthBranch_false cell leading spelling trailing width command different
        have tailResult := inductionHypothesis tailOutcome tailCovered
        exact sequence_next _ _ _ _ _ branch tailResult

theorem body_evaluates_of_outcomes
    (cell : CellId) (leading spelling trailing : List Int) (expected : Value)
    (outcome : ∀ width command, (width, command) ∈ branchCommands →
      spelling.length = width →
      KeywordChoice.Outcome
        (Model.keywordWorld cell (leading ++ spelling ++ trailing))
        (KeywordSemantics.lengthEnvironment cell leading spelling trailing)
        expected command)
    (covered : spelling.length ∈ branchCommands.map Prod.fst ∨
      expected = .signed .i32 (Int.ofNat Compiler.TokenKind.identifier.gpuCode)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading spelling trailing) body =
    some (.returned (some expected), Model.keywordWorld cell (leading ++ spelling ++ trailing),
      KeywordSemantics.lengthEnvironment cell leading spelling trailing) := by
  simpa [body] using branchSequence_evaluates branchCommands cell leading spelling trailing
    expected outcome covered

theorem lengthInitializer_evaluates
    (cell : CellId) (leading spelling trailing : List Int)
    (bounded : spelling.length ≤ 2147483647) :
    Term.evaluate TM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (Model.keywordEnvironment cell (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length))
      (KeywordCommand.directBinary .subtract (KeywordCommand.directSlot 2)
        (KeywordCommand.directSlot 1) KeywordCommand.i32) =
    .ok (.signed .i32 (Int.ofNat spelling.length),
      Model.keywordWorld cell (leading ++ spelling ++ trailing)) := by
  simp only [TM, KeywordSemantics.TM, KeywordCommand.directBinary,
    KeywordCommand.directSlot, Term.evaluate, Ref.evaluate, evaluateTerms,
    Model.keywordEnvironment, bind, Except.bind]
  change Lanius.FunctionalView.Core.Effectful.evaluateOperation
    verifiedFrontendCore Model.noCalls
    (Model.keywordWorld cell (leading ++ spelling ++ trailing))
    (.binary .subtract KeywordCommand.i32 KeywordCommand.i32
      KeywordCommand.i32)
    [.signed .i32 (Int.ofNat (leading.length + spelling.length)),
      .signed .i32 (Int.ofNat leading.length)] = _
  rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
      (by rfl)]
  simp only [Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    Lanius.Semantics.evalBinaryValue, Lanius.Semantics.evalSignedBinary,
    bind, Except.bind]
  rw [KeywordSemantics.wrapSigned_i32_difference leading.length spelling.length
    bounded]
  rfl

theorem command_evaluates_of_body
    (cell : CellId) (leading spelling trailing : List Int) (result : Int)
    (bounded : spelling.length ≤ 2147483647)
    (bodyResult :
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld cell (leading ++ spelling ++ trailing))
        (KeywordSemantics.lengthEnvironment cell leading spelling trailing) body =
      some (.returned (some (.signed .i32 result)),
        Model.keywordWorld cell (leading ++ spelling ++ trailing),
        KeywordSemantics.lengthEnvironment cell leading spelling trailing)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (Model.keywordEnvironment cell (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length)) KeywordCommand.command =
    some (.returned (some (.signed .i32 result)),
      Model.keywordWorld cell (leading ++ spelling ++ trailing),
      Model.keywordEnvironment cell (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length)) := by
  let world := Model.keywordWorld cell (leading ++ spelling ++ trailing)
  let environment := Model.keywordEnvironment cell (leading ++ spelling ++ trailing)
    leading.length (leading.length + spelling.length)
  have initializer := lengthInitializer_evaluates cell leading spelling trailing bounded
  rw [show KeywordCommand.command = KeywordCommand.directCommand by rfl,
    directCommand_body]
  apply KeywordSemantics.run_letValue_preserving world environment
    KeywordCommand.i32 _ _ (.signed .i32 (Int.ofNat spelling.length))
    (.returned (some (.signed .i32 result)))
  · simpa [world, environment] using initializer
  · simpa [world, environment, KeywordSemantics.lengthEnvironment]
      using bodyResult

end Lanius.Extraction.CanonicalTokens.KeywordDispatchSemantics
