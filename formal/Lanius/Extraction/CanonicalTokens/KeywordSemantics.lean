import Lanius.Extraction.CanonicalTokens.Model
import Lanius.Extraction.CanonicalTokens.KeywordLengthSemantics
import Lanius.Extraction.CanonicalTokens.KeywordSpecification
import Lanius.Extraction.CanonicalTokens.KeywordTable

namespace Lanius.Extraction.CanonicalTokens.KeywordSemantics

set_option maxRecDepth 100000
set_option maxHeartbeats 1000000

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful

abbrev TM := KeywordLengthSemantics.TM
abbrev SM := KeywordLengthSemantics.SM

theorem wrapSigned_i32_add_ofNat
    (left right : Nat) (bounded : left + right ≤ 2147483647) :
    Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
        (Int.ofNat left + Int.ofNat right) =
      Int.ofNat (left + right) := by
  change Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
      ((left : Int) + (right : Int)) = ((left + right : Nat) : Int)
  rw [← Int.natCast_add]
  exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ bounded

@[simp] theorem wrapSigned_i32_difference
    (left difference : Nat) (bounded : difference ≤ 2147483647) :
    Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
        (Int.ofNat (left + difference) - Int.ofNat left) =
      Int.ofNat difference := by
  change Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
      (((left + difference : Nat) : Int) - (left : Int)) =
    (difference : Int)
  have differenceEq :
      (((left + difference : Nat) : Int) - (left : Int)) =
        (difference : Int) := by
    rw [Int.natCast_add]
    omega
  rw [differenceEq]
  exact Lanius.Semantics.wrapSigned_i32_ofNat _ _ bounded

private def run (cell : CellId) (source : List Int) (start finish : Nat) :=
  Lanius.FunctionalView.Stateful.Acyclic.run?
    (termMachine (evaluateOperation verifiedFrontendCore Model.noCalls))
    (machineWith verifiedFrontendCore
      (evaluateOperation verifiedFrontendCore Model.noCalls))
    (Model.keywordWorld cell source) (Model.keywordEnvironment cell source start finish)
    KeywordCommand.command

private def result? (cell : CellId) (source : List Int) (start finish : Nat) : Option Int :=
  Model.returnedI32? (run cell source start finish)

theorem get_embedded (leading spelling trailing : List Int) (k : Nat)
    (inSpelling : k < spelling.length)
    (inSource : leading.length + k <
      (leading ++ spelling ++ trailing).length) :
    (leading ++ spelling ++ trailing).get
        ⟨leading.length + k, inSource⟩ =
      spelling.get ⟨k, inSpelling⟩ := by
  have options :
      (leading ++ spelling ++ trailing)[leading.length + k]? =
        spelling[k]? := by
    rw [List.append_assoc, List.getElem?_append_right (by omega)]
    simp only [Nat.add_sub_cancel_left]
    exact List.getElem?_append_left inSpelling
  rw [List.get_eq_getElem, List.get_eq_getElem]
  have left := List.getElem?_eq_getElem inSource
  have right := List.getElem?_eq_getElem inSpelling
  rw [options, right] at left
  exact Option.some.inj left.symm

theorem evaluate_embedded_index (cell : CellId) (leading spelling trailing : List Int)
    (k : Nat) (inSpelling : k < spelling.length) :
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
        verifiedFrontendCore
        (Model.keywordWorld cell (leading ++ spelling ++ trailing))
        (.index KeywordCommand.slice KeywordCommand.i32 KeywordCommand.i32)
        [Model.keywordSource cell (leading ++ spelling ++ trailing),
          .signed .i32 (Int.ofNat (leading.length + k))] =
      .ok (.signed .i32 (spelling.get ⟨k, inSpelling⟩),
        Model.keywordWorld cell (leading ++ spelling ++ trailing)) := by
  have inSource : leading.length + k <
      (leading ++ spelling ++ trailing).length := by
    simp only [List.length_append]
    omega
  have found :
      (Model.keywordWorld cell (leading ++ spelling ++ trailing)).i32Slice? cell =
        some (leading ++ spelling ++ trailing) := by
    simp [Model.keywordWorld,
      Lanius.FunctionalView.Core.ReadOnly.World.singleton]
  have evaluated :=
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_index
      (program := verifiedFrontendCore)
      (world := Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (baseType := KeywordCommand.slice)
      (indexType := KeywordCommand.i32)
      (elementType := KeywordCommand.i32)
      (cell := cell) (values := leading ++ spelling ++ trailing)
      (position := leading.length + k) found inSource
  simpa [Model.keywordSource, List.get_eq_getElem,
    List.getElem_append_left inSpelling] using
      evaluated

theorem evaluate_offset (world : World) (environment : Env arity)
    (position : Fin arity)
    (start k : Nat) (loaded : environment position = .signed .i32 start)
    (bounded : start + k ≤ 2147483647) :
    Term.evaluate TM world environment
        (KeywordCommand.directAdd (KeywordCommand.directSlot position)
          (KeywordCommand.directLiteral (Int.ofNat k))) =
      .ok (.signed .i32 (Int.ofNat (start + k)), world) := by
  simp only [KeywordCommand.directAdd, KeywordCommand.directBinary,
    KeywordCommand.directSlot, KeywordCommand.directLiteral]
  rw [Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
    _ (by rfl)]
  apply Lanius.FunctionalView.Core.ReadOnly.Term.evaluate_i32_add
  · exact Lanius.FunctionalView.Term.evaluate_slot loaded
  · rfl
  · exact bounded

theorem evaluate_slot (world : World) (environment : Env arity)
    (position : Fin arity) :
    Term.evaluate TM world environment
        (KeywordCommand.directSlot position) =
      .ok (environment position, world) := by
  simp only [KeywordCommand.directSlot]
  exact Lanius.FunctionalView.Term.evaluate_slot rfl

theorem evaluate_embedded_directIndex (cell : CellId)
    (leading spelling trailing : List Int)
    (environment : Env arity) (basePosition offsetPosition : Fin arity)
    (k : Nat) (inSpelling : k < spelling.length)
    (baseLoaded : environment basePosition =
      Model.keywordSource cell (leading ++ spelling ++ trailing))
    (offsetLoaded : environment offsetPosition = .signed .i32 leading.length)
    (bounded : leading.length + k ≤ 2147483647) :
    Term.evaluate TM
        (Model.keywordWorld cell (leading ++ spelling ++ trailing)) environment
        (KeywordCommand.directIndex (KeywordCommand.directSlot basePosition)
          (KeywordCommand.directAdd (KeywordCommand.directSlot offsetPosition)
            (KeywordCommand.directLiteral (Int.ofNat k)))) =
      .ok (.signed .i32 (spelling.get ⟨k, inSpelling⟩),
        Model.keywordWorld cell (leading ++ spelling ++ trailing)) := by
  simp only [KeywordCommand.directIndex, Term.evaluate, evaluateTerms,
    bind, Except.bind]
  rw [evaluate_slot
    (Model.keywordWorld cell (leading ++ spelling ++ trailing)) environment
    basePosition, baseLoaded]
  simp only
  rw [evaluate_offset
    (Model.keywordWorld cell (leading ++ spelling ++ trailing)) environment
    offsetPosition leading.length k offsetLoaded bounded]
  simp only
  change Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendCore Model.noCalls
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (.index KeywordCommand.slice KeywordCommand.i32 KeywordCommand.i32)
      [Model.keywordSource cell (leading ++ spelling ++ trailing),
        .signed .i32 (Int.ofNat (leading.length + k))] = _
  rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
      (by rfl),
    evaluate_embedded_index cell leading spelling trailing k inSpelling]

theorem evaluate_embedded_directIndex_zero
    (cell : CellId) (leading spelling trailing : List Int)
    (environment : Env arity) (basePosition offsetPosition : Fin arity)
    (nonempty : 0 < spelling.length)
    (baseLoaded : environment basePosition =
      Model.keywordSource cell (leading ++ spelling ++ trailing))
    (offsetLoaded : environment offsetPosition = .signed .i32 leading.length) :
    Term.evaluate TM
        (Model.keywordWorld cell (leading ++ spelling ++ trailing)) environment
        (KeywordCommand.directIndex (KeywordCommand.directSlot basePosition)
          (KeywordCommand.directSlot offsetPosition)) =
      .ok (.signed .i32 (spelling.get ⟨0, nonempty⟩),
        Model.keywordWorld cell (leading ++ spelling ++ trailing)) := by
  simp only [KeywordCommand.directIndex, Term.evaluate, evaluateTerms]
  rw [evaluate_slot
    (Model.keywordWorld cell (leading ++ spelling ++ trailing)) environment
    basePosition, baseLoaded]
  simp only [bind, Except.bind]
  rw [evaluate_slot
    (Model.keywordWorld cell (leading ++ spelling ++ trailing)) environment
    offsetPosition, offsetLoaded]
  change Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendCore Model.noCalls
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (.index KeywordCommand.slice KeywordCommand.i32 KeywordCommand.i32)
      [Model.keywordSource cell (leading ++ spelling ++ trailing),
        .signed .i32 (Int.ofNat leading.length)] = _
  rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
      (by rfl)]
  exact evaluate_embedded_index cell leading spelling trailing 0 nonempty

def lengthEnvironment (cell : CellId) (leading spelling trailing : List Int) : Env 4 :=
  (Model.keywordEnvironment cell (leading ++ spelling ++ trailing) leading.length
    (leading.length + spelling.length)).push
      (.signed .i32 (Int.ofNat spelling.length))

/-- A checked local binding whose body preserves its extended environment
can be discharged without exposing the implementation of `run?`.  This is
the reusable semantic rule behind every fixed-width keyword-byte load. -/
theorem run_letValue_preserving
    (world : World) (environment : Env arity) (type : Ty)
    (initializer : Term Core.signature arity)
    (body : Stateful.Command Core.signature actions (arity + 1))
    (value : Value) (completion : Stateful.Completion)
    (initializerResult : Term.evaluate TM world environment initializer =
      .ok (value, world))
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world
      (environment.push value) body =
        some (completion, world, environment.push value)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world environment
        (.letValue type initializer body) =
      some (completion, world, environment) := by
  simp only [Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [initializerResult]
  simp only
  rw [bodyResult]
  simp only [Stateful.Env.pop_push]

def loaded1Environment (cell : CellId) (leading spelling trailing : List Int)
    (first : Int) : Env (4 + 1) :=
  (lengthEnvironment cell leading spelling trailing).push (.signed .i32 first)

def loaded2Environment (cell : CellId) (leading spelling trailing : List Int)
    (first second : Int) : Env (4 + 1 + 1) :=
  (loaded1Environment cell leading spelling trailing first).push
    (.signed .i32 second)

def loaded3Environment (cell : CellId) (leading spelling trailing : List Int)
    (first second third : Int) : Env (4 + 1 + 1 + 1) :=
  (loaded2Environment cell leading spelling trailing first second).push
    (.signed .i32 third)

def loaded4Environment (cell : CellId) (leading spelling trailing : List Int)
    (first second third fourth : Int) : Env (4 + 1 + 1 + 1 + 1) :=
  (loaded3Environment cell leading spelling trailing first second third).push
    (.signed .i32 fourth)

def loaded5Environment (cell : CellId) (leading spelling trailing : List Int)
    (first second third fourth fifth : Int) : Env (4 + 1 + 1 + 1 + 1 + 1) :=
  (loaded4Environment cell leading spelling trailing first second third fourth).push
    (.signed .i32 fifth)

def loaded6Environment (cell : CellId) (leading spelling trailing : List Int)
    (first second third fourth fifth sixth : Int) : Env (4 + 1 + 1 + 1 + 1 + 1 + 1) :=
  (loaded5Environment cell leading spelling trailing first second third fourth fifth).push
    (.signed .i32 sixth)

def loaded7Environment (cell : CellId) (leading spelling trailing : List Int)
    (first second third fourth fifth sixth seventh : Int) : Env (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1) :=
  (loaded6Environment cell leading spelling trailing first second third fourth fifth sixth).push
    (.signed .i32 seventh)

def loaded8Environment (cell : CellId) (leading spelling trailing : List Int)
    (first second third fourth fifth sixth seventh eighth : Int) : Env (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1) :=
  (loaded7Environment cell leading spelling trailing first second third fourth fifth sixth seventh).push
    (.signed .i32 eighth)

theorem directLoad2_evaluates_of_body
    (cell : CellId) (leading spelling trailing : List Int)
    (first second : Int)
    (body : KeywordCommand.C 6) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (loaded2Environment cell leading spelling trailing first second) body =
        some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
          loaded2Environment cell leading spelling trailing first second)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld cell (leading ++ spelling ++ trailing))
        (lengthEnvironment cell leading spelling trailing)
        (KeywordCommand.directLoad2 body) =
      some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
        lengthEnvironment cell leading spelling trailing) := by
  subst spelling
  simp only [List.length_append, List.length_cons, List.length_nil] at bounded
  let world := Model.keywordWorld cell (leading ++ [first, second] ++ trailing)
  let base := lengthEnvironment cell leading [first, second] trailing
  unfold KeywordCommand.directLoad2
  apply run_letValue_preserving world
  · apply evaluate_embedded_directIndex_zero cell <;>
      simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
  · repeat' first
    | apply run_letValue_preserving world
      · apply evaluate_embedded_directIndex cell <;>
          simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
    simpa [world, base, loaded2Environment, loaded1Environment] using bodyResult

theorem length2Rules_loaded
    (cell : CellId) (leading trailing : List Int) (first second : Int) :
    ∀ bytes constant,
      (bytes, constant) ∈ KeywordCommand.length2Rules →
        ∀ position expected, (position, expected) ∈ bytes →
          ∃ actual,
            loaded2Environment cell leading [first, second] trailing first second
              position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length2Rules] at member
  rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp at byteMember <;>
    rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    all_goals exact ⟨_, rfl⟩

theorem directLoad3_evaluates_of_body
    (cell : CellId) (leading spelling trailing : List Int)
    (first second third : Int)
    (body : KeywordCommand.C 7) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second, third])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (loaded3Environment cell leading spelling trailing first second third) body =
        some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
          loaded3Environment cell leading spelling trailing first second third)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld cell (leading ++ spelling ++ trailing))
        (lengthEnvironment cell leading spelling trailing)
        (KeywordCommand.directLoad3 body) =
      some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
          lengthEnvironment cell leading spelling trailing) := by
  subst spelling
  simp only [List.length_append, List.length_cons, List.length_nil] at bounded
  let world := Model.keywordWorld cell (leading ++ [first, second, third] ++ trailing)
  let base := lengthEnvironment cell leading [first, second, third] trailing
  unfold KeywordCommand.directLoad3
  apply run_letValue_preserving world
  · apply evaluate_embedded_directIndex_zero cell <;>
      simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
  · repeat' first
    | apply run_letValue_preserving world
      · apply evaluate_embedded_directIndex cell <;>
          simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
    simpa [world, base, loaded3Environment, loaded2Environment,
      loaded1Environment] using bodyResult

theorem length3Rules_loaded
    (cell : CellId) (leading trailing : List Int) (first second third : Int) :
    ∀ bytes constant,
      (bytes, constant) ∈ KeywordCommand.length3Rules →
        ∀ position expected, (position, expected) ∈ bytes →
          ∃ actual,
            loaded3Environment cell leading [first, second, third] trailing
              first second third position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length3Rules] at member
  rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp at byteMember <;>
    rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    all_goals exact ⟨_, rfl⟩

theorem directLoad4_evaluates_of_body
    (cell : CellId) (leading spelling trailing : List Int)
    (first second third fourth : Int)
    (body : KeywordCommand.C 8) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second, third, fourth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (loaded4Environment cell leading spelling trailing first second third fourth)
      body = some (completion,
        Model.keywordWorld cell (leading ++ spelling ++ trailing),
        loaded4Environment cell leading spelling trailing first second third fourth)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld cell (leading ++ spelling ++ trailing))
        (lengthEnvironment cell leading spelling trailing)
        (KeywordCommand.directLoad4 body) =
      some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
        lengthEnvironment cell leading spelling trailing) := by
  subst spelling
  simp only [List.length_append, List.length_cons, List.length_nil] at bounded
  let world := Model.keywordWorld cell
    (leading ++ [first, second, third, fourth] ++ trailing)
  let base := lengthEnvironment cell leading [first, second, third, fourth] trailing
  unfold KeywordCommand.directLoad4
  apply run_letValue_preserving world
  · apply evaluate_embedded_directIndex_zero cell <;>
      simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
  · repeat' first
    | apply run_letValue_preserving world
      · apply evaluate_embedded_directIndex cell <;>
          simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
    have at3 : [first, second, third, fourth][(⟨3, by simp⟩ : Fin 4).val] = fourth := by rfl
    have fin3 : ((3 : Fin 4).val) = 3 := by decide
    simpa [world, base, loaded4Environment, loaded3Environment,
      loaded2Environment, loaded1Environment, at3, fin3] using bodyResult

theorem length4Rules_loaded
    (cell : CellId) (leading trailing : List Int) (first second third fourth : Int) :
    ∀ bytes constant,
      (bytes, constant) ∈ KeywordCommand.length4Rules →
        ∀ position expected, (position, expected) ∈ bytes →
          ∃ actual, loaded4Environment cell leading
            [first, second, third, fourth] trailing first second third fourth
              position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length4Rules] at member
  rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
      ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp at byteMember <;>
    rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
      ⟨rfl, rfl⟩ <;>
    all_goals exact ⟨_, rfl⟩

theorem directLoad5_evaluates_of_body
    (cell : CellId) (leading spelling trailing : List Int)
    (first second third fourth fifth : Int)
    (body : KeywordCommand.C 9) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second, third, fourth, fifth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (loaded5Environment cell leading spelling trailing first second third fourth fifth) body =
        some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
          loaded5Environment cell leading spelling trailing first second third fourth fifth)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (lengthEnvironment cell leading spelling trailing)
      (KeywordCommand.directLoad5 body) =
        some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
          lengthEnvironment cell leading spelling trailing) := by
  subst spelling
  simp only [List.length_append, List.length_cons, List.length_nil] at bounded
  let world := Model.keywordWorld cell (leading ++ [first, second, third, fourth, fifth] ++ trailing)
  let base := lengthEnvironment cell leading [first, second, third, fourth, fifth] trailing
  unfold KeywordCommand.directLoad5
  apply run_letValue_preserving world
  · apply evaluate_embedded_directIndex_zero cell <;>
      simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
  · repeat' first
    | apply run_letValue_preserving world
      · apply evaluate_embedded_directIndex cell <;>
          simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
    have at3 : [first, second, third, fourth, fifth][(⟨3, by simp⟩ : Fin 5).val] = fourth := by rfl
    have at4 : [first, second, third, fourth, fifth][(⟨4, by simp⟩ : Fin 5).val] = fifth := by rfl
    have fin3 : ((3 : Fin 5).val) = 3 := by decide
    have fin4 : ((4 : Fin 5).val) = 4 := by decide
    simpa [world, base, loaded5Environment, loaded4Environment,
      loaded3Environment, loaded2Environment, loaded1Environment,
      at3, at4, fin3, fin4] using bodyResult


theorem length5Rules_loaded
    (cell : CellId) (leading trailing : List Int)
    (first second third fourth fifth : Int) :
    ∀ bytes constant, (bytes, constant) ∈ KeywordCommand.length5Rules →
      ∀ position expected, (position, expected) ∈ bytes →
        ∃ actual, loaded5Environment cell leading [first, second, third, fourth, fifth] trailing first second third fourth fifth
          position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length5Rules] at member
  rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp at byteMember <;>
    rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    all_goals exact ⟨_, rfl⟩

theorem directLoad6_evaluates_of_body
    (cell : CellId) (leading spelling trailing : List Int)
    (first second third fourth fifth sixth : Int)
    (body : KeywordCommand.C 10) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second, third, fourth, fifth, sixth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (loaded6Environment cell leading spelling trailing first second third fourth fifth sixth) body =
      some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
        loaded6Environment cell leading spelling trailing first second third fourth fifth sixth)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (lengthEnvironment cell leading spelling trailing) (KeywordCommand.directLoad6 body) =
      some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
        lengthEnvironment cell leading spelling trailing) := by
  subst spelling
  simp only [List.length_append, List.length_cons, List.length_nil] at bounded
  let world := Model.keywordWorld cell (leading ++ [first, second, third, fourth, fifth, sixth] ++ trailing)
  let base := lengthEnvironment cell leading [first, second, third, fourth, fifth, sixth] trailing
  unfold KeywordCommand.directLoad6
  apply run_letValue_preserving world
  · apply evaluate_embedded_directIndex_zero cell <;>
      simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
  · repeat' first
    | apply run_letValue_preserving world
      · apply evaluate_embedded_directIndex cell <;>
          simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
    have at3 : [first, second, third, fourth, fifth, sixth][(⟨3, by simp⟩ : Fin 6).val] = fourth := by rfl
    have at4 : [first, second, third, fourth, fifth, sixth][(⟨4, by simp⟩ : Fin 6).val] = fifth := by rfl
    have at5 : [first, second, third, fourth, fifth, sixth][(⟨5, by simp⟩ : Fin 6).val] = sixth := by rfl
    have fin3 : ((3 : Fin 6).val) = 3 := by decide
    have fin4 : ((4 : Fin 6).val) = 4 := by decide
    have fin5 : ((5 : Fin 6).val) = 5 := by decide
    simpa [world, base, loaded6Environment, loaded5Environment,
      loaded4Environment, loaded3Environment, loaded2Environment,
      loaded1Environment, at3, at4, at5, fin3, fin4, fin5] using bodyResult

theorem length6Rules_loaded
    (cell : CellId) (leading trailing : List Int)
    (first second third fourth fifth sixth : Int) :
    ∀ bytes constant, (bytes, constant) ∈ KeywordCommand.length6Rules →
      ∀ position expected, (position, expected) ∈ bytes →
        ∃ actual, loaded6Environment cell leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth
          position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length6Rules] at member
  rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp at byteMember <;>
    rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    all_goals exact ⟨_, rfl⟩

theorem directLoad8_evaluates_of_body
    (cell : CellId) (leading spelling trailing : List Int)
    (first second third fourth fifth sixth seventh eighth : Int)
    (body : KeywordCommand.C 12) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second, third, fourth, fifth, sixth, seventh, eighth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (loaded8Environment cell leading spelling trailing first second third fourth fifth sixth seventh eighth) body =
      some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
        loaded8Environment cell leading spelling trailing first second third fourth fifth sixth seventh eighth)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (lengthEnvironment cell leading spelling trailing) (KeywordCommand.directLoad8 body) =
      some (completion, Model.keywordWorld cell (leading ++ spelling ++ trailing),
        lengthEnvironment cell leading spelling trailing) := by
  subst spelling
  simp only [List.length_append, List.length_cons, List.length_nil] at bounded
  let world := Model.keywordWorld cell (leading ++ [first, second, third, fourth, fifth, sixth, seventh, eighth] ++ trailing)
  let base := lengthEnvironment cell leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
  unfold KeywordCommand.directLoad8
  apply run_letValue_preserving world
  · apply evaluate_embedded_directIndex_zero cell <;>
      simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
  · repeat' first
    | apply run_letValue_preserving world
      · apply evaluate_embedded_directIndex cell <;>
          simp [lengthEnvironment, Model.keywordEnvironment] <;> omega
    have at3 : [first, second, third, fourth, fifth, sixth, seventh, eighth][(⟨3, by simp⟩ : Fin 8).val] = fourth := by rfl
    have at4 : [first, second, third, fourth, fifth, sixth, seventh, eighth][(⟨4, by simp⟩ : Fin 8).val] = fifth := by rfl
    have at5 : [first, second, third, fourth, fifth, sixth, seventh, eighth][(⟨5, by simp⟩ : Fin 8).val] = sixth := by rfl
    have at6 : [first, second, third, fourth, fifth, sixth, seventh, eighth][(⟨6, by simp⟩ : Fin 8).val] = seventh := by rfl
    have at7 : [first, second, third, fourth, fifth, sixth, seventh, eighth][(⟨7, by simp⟩ : Fin 8).val] = eighth := by rfl
    have fin3 : ((3 : Fin 8).val) = 3 := by decide
    have fin4 : ((4 : Fin 8).val) = 4 := by decide
    have fin5 : ((5 : Fin 8).val) = 5 := by decide
    have fin6 : ((6 : Fin 8).val) = 6 := by decide
    have fin7 : ((7 : Fin 8).val) = 7 := by decide
    simpa [world, base, loaded8Environment, loaded7Environment,
      loaded6Environment, loaded5Environment, loaded4Environment,
      loaded3Environment, loaded2Environment, loaded1Environment,
      at3, at4, at5, at6, at7, fin3, fin4, fin5, fin6, fin7] using bodyResult

theorem length8Rules_loaded
    (cell : CellId) (leading trailing : List Int)
    (first second third fourth fifth sixth seventh eighth : Int) :
    ∀ bytes constant, (bytes, constant) ∈ KeywordCommand.length8Rules →
      ∀ position expected, (position, expected) ∈ bytes →
        ∃ actual, loaded8Environment cell leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth
          position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length8Rules] at member
  rcases member with ⟨rfl, rfl⟩
  simp at byteMember
  rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    all_goals exact ⟨_, rfl⟩

def decisionValue (environment : Env arity)
    (rules : List (List (Fin arity × Int) × ConstantId)) : Option Value :=
  let id := (KeywordLengthSemantics.firstMatchingConstant environment rules).getD 7
  (verifiedFrontendCore.constant? id).map (fun declaration => declaration.value)

theorem length3_decisionValue
    (cell : CellId) (leading trailing : List Int) (first second third : Int) :
    decisionValue (loaded3Environment cell leading [first, second, third] trailing first second third)
      KeywordCommand.length3Rules =
    some (.signed .i32 (Model.keywordKind [first, second, third] 0 3)) := by
  unfold decisionValue
  apply KeywordTable.decision_reference
    (query := [first, second, third])
  · intro bytes constant member
    simp [KeywordCommand.length3Rules] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    all_goals
      simp (disch := decide) only [KeywordLengthSemantics.ruleMatches,
        OfNat.ofNat, Fin.ofNat, Nat.mod_eq_of_lt,
        loaded3Environment, loaded2Environment, loaded1Environment,
        lengthEnvironment, Env.push_of_lt, Env.push_last,
        Bool.and_eq_true, List.map,
        beq_iff_eq, List.cons.injEq, and_true]
  · intro bytes constant member
    simp [KeywordCommand.length3Rules] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    all_goals exact ⟨_, rfl, rfl⟩
  · simp [KeywordTable.tableRows, KeywordTable.ruleQuery,
      KeywordCommand.length3Rules, Dispatch.referenceRows]
    decide


theorem length4_decisionValue
    (cell : CellId) (leading trailing : List Int) (first second third fourth : Int) :
    decisionValue (loaded4Environment cell leading [first, second, third, fourth] trailing first second third fourth)
      KeywordCommand.length4Rules =
    some (.signed .i32 (Model.keywordKind [first, second, third, fourth] 0 4)) := by
  unfold decisionValue
  apply KeywordTable.decision_reference
    (query := [first, second, third, fourth])
  · intro bytes constant member
    simp [KeywordCommand.length4Rules] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
      ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    all_goals
      simp (disch := decide) only [KeywordLengthSemantics.ruleMatches,
        OfNat.ofNat, Fin.ofNat, Nat.mod_eq_of_lt,
        loaded4Environment, loaded3Environment, loaded2Environment,
        loaded1Environment, lengthEnvironment, Env.push_of_lt, Env.push_last,
        Bool.and_eq_true, List.map, beq_iff_eq,
        List.cons.injEq, and_true]
  · intro bytes constant member
    simp [KeywordCommand.length4Rules] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
      ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    all_goals exact ⟨_, rfl, rfl⟩
  · simp [KeywordTable.tableRows, KeywordTable.ruleQuery,
      KeywordCommand.length4Rules, Dispatch.referenceRows]
    decide


theorem length2_decisionValue
    (cell : CellId) (leading trailing : List Int) (first second : Int) :
    decisionValue
      (loaded2Environment cell leading [first, second] trailing first second)
      KeywordCommand.length2Rules =
    some (.signed .i32 (Model.keywordKind [first, second] 0 2)) := by
  unfold decisionValue
  apply KeywordTable.decision_reference
    (query := [first, second])
  · intro bytes constant member
    simp [KeywordCommand.length2Rules] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    all_goals
      simp (disch := decide) only [KeywordLengthSemantics.ruleMatches,
        OfNat.ofNat, Fin.ofNat, Nat.mod_eq_of_lt,
        loaded2Environment, loaded1Environment, lengthEnvironment,
        Env.push_of_lt, Env.push_last,
        Bool.and_eq_true, List.map, beq_iff_eq,
        List.cons.injEq, and_true]
  · intro bytes constant member
    simp [KeywordCommand.length2Rules] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    all_goals exact ⟨_, rfl, rfl⟩
  · simp [KeywordTable.tableRows, KeywordTable.ruleQuery,
      KeywordCommand.length2Rules, Dispatch.referenceRows]
    decide


end Lanius.Extraction.CanonicalTokens.KeywordSemantics
