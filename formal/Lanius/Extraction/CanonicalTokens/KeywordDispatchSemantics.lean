import Lanius.Extraction.CanonicalTokens.KeywordDecision5
import Lanius.Extraction.CanonicalTokens.KeywordDecision6
import Lanius.Extraction.CanonicalTokens.KeywordDecision8

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

def body : KeywordCommand.C 4 :=
  .sequence (KeywordCommand.directLengthBranch 2
      (KeywordCommand.directLoad2
        (KeywordCommand.directChoices KeywordCommand.length2Rules)))
    (.sequence (KeywordCommand.directLengthBranch 3
        (KeywordCommand.directLoad3
          (KeywordCommand.directChoices KeywordCommand.length3Rules)))
      (.sequence (KeywordCommand.directLengthBranch 4
          (KeywordCommand.directLoad4
            (KeywordCommand.directChoices KeywordCommand.length4Rules)))
        (.sequence (KeywordCommand.directLengthBranch 5
            (KeywordCommand.directLoad5
              (KeywordCommand.directChoices KeywordCommand.length5Rules)))
          (.sequence (KeywordCommand.directLengthBranch 6
              (KeywordCommand.directLoad6
                (KeywordCommand.directChoices KeywordCommand.length6Rules)))
            (.sequence (KeywordCommand.directLengthBranch 8
                (KeywordCommand.directLoad8
                  (KeywordCommand.directChoices KeywordCommand.length8Rules)))
              (KeywordCommand.directReturned
                (KeywordCommand.directConstant 7)))))))

theorem directCommand_body : KeywordCommand.directCommand =
    .letValue KeywordCommand.i32
      (KeywordCommand.directBinary .subtract (KeywordCommand.directSlot 2)
        (KeywordCommand.directSlot 1) KeywordCommand.i32) body := by
  rfl

@[simp] theorem lengthEnvironment_last
    (leading spelling trailing : List Int) :
    KeywordSemantics.lengthEnvironment leading spelling trailing
      ⟨3, by decide⟩ = .signed .i32 (Int.ofNat spelling.length) := by
  unfold KeywordSemantics.lengthEnvironment
  rw [Env.push_last]

theorem lengthCondition_evaluates
    (leading spelling trailing : List Int) (expected : Int) :
    Term.evaluate TM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment leading spelling trailing)
      (KeywordCommand.directEqual (KeywordCommand.directSlot 3)
        (KeywordCommand.directLiteral expected)) =
    .ok (.boolean (Int.ofNat spelling.length == expected),
      Model.keywordWorld (leading ++ spelling ++ trailing)) := by
  apply KeywordLengthSemantics.directEqual_evaluates
    (environment := KeywordSemantics.lengthEnvironment leading spelling trailing)
    (position := ⟨3, by decide⟩)
    (actual := Int.ofNat spelling.length)
    (expected := expected)
  exact lengthEnvironment_last leading spelling trailing

theorem lengthBranch_false
    (leading spelling trailing : List Int) (expected : Int)
    (body : KeywordCommand.C 4)
    (different : (Int.ofNat spelling.length == expected) = false) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment leading spelling trailing)
      (KeywordCommand.directLengthBranch expected body) =
    some (.next, Model.keywordWorld (leading ++ spelling ++ trailing),
      KeywordSemantics.lengthEnvironment leading spelling trailing) := by
  have condition := lengthCondition_evaluates leading spelling trailing expected
  rw [different] at condition
  unfold KeywordCommand.directLengthBranch
  simp only [Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [condition]
  rfl

theorem lengthBranch_true
    (leading spelling trailing : List Int) (expected : Int)
    (body : KeywordCommand.C 4) (completion : Stateful.Completion)
    (same : (Int.ofNat spelling.length == expected) = true)
    (bodyResult :
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (KeywordSemantics.lengthEnvironment leading spelling trailing) body =
      some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
        KeywordSemantics.lengthEnvironment leading spelling trailing)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment leading spelling trailing)
      (KeywordCommand.directLengthBranch expected body) =
    some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
      KeywordSemantics.lengthEnvironment leading spelling trailing) := by
  have condition := lengthCondition_evaluates leading spelling trailing expected
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
  rfl

theorem identifier_return_evaluates
    (leading spelling trailing : List Int) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment leading spelling trailing)
      (KeywordCommand.directReturned (KeywordCommand.directConstant 7)) =
    some (.returned
      (some (.signed .i32 (Int.ofNat Compiler.TokenKind.identifier.gpuCode))),
      Model.keywordWorld (leading ++ spelling ++ trailing),
      KeywordSemantics.lengthEnvironment leading spelling trailing) := by
  have constant : verifiedFrontendCore.constant? 7 = some {
      id := 7, type := KeywordCommand.i32,
      value := .signed .i32 (Int.ofNat Compiler.TokenKind.identifier.gpuCode) } := by
    rfl
  have evaluated := KeywordLengthSemantics.directConstant_evaluates
    (world := Model.keywordWorld (leading ++ spelling ++ trailing))
    (environment := KeywordSemantics.lengthEnvironment leading spelling trailing)
    (constant := 7) _ constant
  unfold KeywordCommand.directReturned
  simp only [Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [evaluated]
  rfl

theorem lengthInitializer_evaluates
    (leading spelling trailing : List Int)
    (bounded : spelling.length ≤ 2147483647) :
    Term.evaluate TM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (Model.keywordEnvironment (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length))
      (KeywordCommand.directBinary .subtract (KeywordCommand.directSlot 2)
        (KeywordCommand.directSlot 1) KeywordCommand.i32) =
    .ok (.signed .i32 (Int.ofNat spelling.length),
      Model.keywordWorld (leading ++ spelling ++ trailing)) := by
  simp only [TM, KeywordSemantics.TM, KeywordCommand.directBinary,
    KeywordCommand.directSlot, Term.evaluate, Ref.evaluate, evaluateTerms,
    Model.keywordEnvironment, bind, Except.bind]
  change Lanius.FunctionalView.Core.Effectful.evaluateOperation
    verifiedFrontendCore Model.noCalls
    (Model.keywordWorld (leading ++ spelling ++ trailing))
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
    (leading spelling trailing : List Int) (result : Int)
    (bounded : spelling.length ≤ 2147483647)
    (bodyResult :
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (KeywordSemantics.lengthEnvironment leading spelling trailing) body =
      some (.returned (some (.signed .i32 result)),
        Model.keywordWorld (leading ++ spelling ++ trailing),
        KeywordSemantics.lengthEnvironment leading spelling trailing)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (Model.keywordEnvironment (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length)) KeywordCommand.command =
    some (.returned (some (.signed .i32 result)),
      Model.keywordWorld (leading ++ spelling ++ trailing),
      Model.keywordEnvironment (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length)) := by
  let world := Model.keywordWorld (leading ++ spelling ++ trailing)
  let environment := Model.keywordEnvironment (leading ++ spelling ++ trailing)
    leading.length (leading.length + spelling.length)
  have initializer := lengthInitializer_evaluates leading spelling trailing bounded
  rw [show KeywordCommand.command = KeywordCommand.directCommand by rfl,
    directCommand_body]
  apply KeywordSemantics.run_letValue_preserving world environment
    KeywordCommand.i32 _ _ (.signed .i32 (Int.ofNat spelling.length))
    (.returned (some (.signed .i32 result)))
  · simpa [world, environment] using initializer
  · simpa [world, environment, KeywordSemantics.lengthEnvironment]
      using bodyResult

end Lanius.Extraction.CanonicalTokens.KeywordDispatchSemantics
