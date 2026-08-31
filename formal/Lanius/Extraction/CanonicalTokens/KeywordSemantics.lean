import Lanius.Extraction.CanonicalTokens.Model
import Lanius.Extraction.CanonicalTokens.KeywordLengthSemantics
import Lanius.Extraction.CanonicalTokens.KeywordSpecification

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

private def run (source : List Int) (start finish : Nat) :=
  Lanius.FunctionalView.Stateful.Acyclic.run?
    (termMachine (evaluateOperation verifiedFrontendCore Model.noCalls))
    (machineWith verifiedFrontendCore
      (evaluateOperation verifiedFrontendCore Model.noCalls))
    (Model.keywordWorld source) (Model.keywordEnvironment source start finish)
    KeywordCommand.command

private def result? (source : List Int) (start finish : Nat) : Option Int :=
  Model.returnedI32? (run source start finish)

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

theorem evaluate_embedded_index (leading spelling trailing : List Int)
    (k : Nat) (inSpelling : k < spelling.length) :
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
        verifiedFrontendCore
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (.index KeywordCommand.slice KeywordCommand.i32 KeywordCommand.i32)
        [Model.keywordSource (leading ++ spelling ++ trailing),
          .signed .i32 (Int.ofNat (leading.length + k))] =
      .ok (.signed .i32 (spelling.get ⟨k, inSpelling⟩),
        Model.keywordWorld (leading ++ spelling ++ trailing)) := by
  have inSource : leading.length + k <
      (leading ++ spelling ++ trailing).length := by
    simp only [List.length_append]
    omega
  have found :
      (Model.keywordWorld (leading ++ spelling ++ trailing)).i32Slice? 0 =
        some (leading ++ spelling ++ trailing) := by
    simp [Model.keywordWorld,
      Lanius.FunctionalView.Core.ReadOnly.World.singleton]
  have evaluated :=
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_index
      (program := verifiedFrontendCore)
      (world := Model.keywordWorld (leading ++ spelling ++ trailing))
      (baseType := KeywordCommand.slice)
      (indexType := KeywordCommand.i32)
      (elementType := KeywordCommand.i32)
      (cell := 0) (values := leading ++ spelling ++ trailing)
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
  simp only [TM, KeywordLengthSemantics.TM, termMachine,
    KeywordCommand.directAdd, KeywordCommand.directSlot,
    KeywordCommand.directLiteral, KeywordCommand.directBinary,
    Term.evaluate, Ref.evaluate, evaluateTerms, loaded, bind, Except.bind]
  rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
      (by rfl)]
  simp [Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    Lanius.Semantics.evalBinaryValue, Lanius.Semantics.evalSignedBinary,
    bind, Except.bind]
  calc
    Lanius.Semantics.wrapSigned verifiedFrontendCore.target .i32
        (Int.ofNat start + Int.ofNat k) = Int.ofNat (start + k) :=
      wrapSigned_i32_add_ofNat start k bounded
    _ = Int.ofNat start + Int.ofNat k := Int.natCast_add start k

theorem evaluate_slot (world : World) (environment : Env arity)
    (position : Fin arity) :
    Term.evaluate TM world environment
        (KeywordCommand.directSlot position) =
      .ok (environment position, world) := by
  simp [TM, KeywordLengthSemantics.TM, termMachine,
    KeywordCommand.directSlot, Ref.evaluate]

theorem evaluate_embedded_directIndex (leading spelling trailing : List Int)
    (environment : Env arity) (basePosition offsetPosition : Fin arity)
    (k : Nat) (inSpelling : k < spelling.length)
    (baseLoaded : environment basePosition =
      Model.keywordSource (leading ++ spelling ++ trailing))
    (offsetLoaded : environment offsetPosition = .signed .i32 leading.length)
    (bounded : leading.length + k ≤ 2147483647) :
    Term.evaluate TM
        (Model.keywordWorld (leading ++ spelling ++ trailing)) environment
        (KeywordCommand.directIndex (KeywordCommand.directSlot basePosition)
          (KeywordCommand.directAdd (KeywordCommand.directSlot offsetPosition)
            (KeywordCommand.directLiteral (Int.ofNat k)))) =
      .ok (.signed .i32 (spelling.get ⟨k, inSpelling⟩),
        Model.keywordWorld (leading ++ spelling ++ trailing)) := by
  simp only [KeywordCommand.directIndex, Term.evaluate, evaluateTerms,
    bind, Except.bind]
  rw [evaluate_slot
    (Model.keywordWorld (leading ++ spelling ++ trailing)) environment
    basePosition, baseLoaded]
  simp only
  rw [evaluate_offset
    (Model.keywordWorld (leading ++ spelling ++ trailing)) environment
    offsetPosition leading.length k offsetLoaded bounded]
  simp only
  change Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendCore Model.noCalls
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (.index KeywordCommand.slice KeywordCommand.i32 KeywordCommand.i32)
      [Model.keywordSource (leading ++ spelling ++ trailing),
        .signed .i32 (Int.ofNat (leading.length + k))] = _
  rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
      (by rfl),
    evaluate_embedded_index leading spelling trailing k inSpelling]
  rfl

theorem evaluate_embedded_directIndex_zero
    (leading spelling trailing : List Int)
    (environment : Env arity) (basePosition offsetPosition : Fin arity)
    (nonempty : 0 < spelling.length)
    (baseLoaded : environment basePosition =
      Model.keywordSource (leading ++ spelling ++ trailing))
    (offsetLoaded : environment offsetPosition = .signed .i32 leading.length) :
    Term.evaluate TM
        (Model.keywordWorld (leading ++ spelling ++ trailing)) environment
        (KeywordCommand.directIndex (KeywordCommand.directSlot basePosition)
          (KeywordCommand.directSlot offsetPosition)) =
      .ok (.signed .i32 (spelling.get ⟨0, nonempty⟩),
        Model.keywordWorld (leading ++ spelling ++ trailing)) := by
  simp only [KeywordCommand.directIndex, Term.evaluate, evaluateTerms]
  rw [evaluate_slot
    (Model.keywordWorld (leading ++ spelling ++ trailing)) environment
    basePosition, baseLoaded]
  simp only [bind, Except.bind]
  rw [evaluate_slot
    (Model.keywordWorld (leading ++ spelling ++ trailing)) environment
    offsetPosition, offsetLoaded]
  change Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendCore Model.noCalls
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (.index KeywordCommand.slice KeywordCommand.i32 KeywordCommand.i32)
      [Model.keywordSource (leading ++ spelling ++ trailing),
        .signed .i32 (Int.ofNat leading.length)] = _
  rw [Lanius.FunctionalView.Core.Effectful.evaluateOperation_eq_readOnly_of_callFree
      (by rfl)]
  exact evaluate_embedded_index leading spelling trailing 0 nonempty

def lengthEnvironment (leading spelling trailing : List Int) : Env 4 :=
  (Model.keywordEnvironment (leading ++ spelling ++ trailing) leading.length
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
  rfl

def loaded1Environment (leading spelling trailing : List Int)
    (first : Int) : Env (4 + 1) :=
  (lengthEnvironment leading spelling trailing).push (.signed .i32 first)

def loaded2Environment (leading spelling trailing : List Int)
    (first second : Int) : Env (4 + 1 + 1) :=
  (loaded1Environment leading spelling trailing first).push
    (.signed .i32 second)

def loaded3Environment (leading spelling trailing : List Int)
    (first second third : Int) : Env (4 + 1 + 1 + 1) :=
  (loaded2Environment leading spelling trailing first second).push
    (.signed .i32 third)

def loaded4Environment (leading spelling trailing : List Int)
    (first second third fourth : Int) : Env (4 + 1 + 1 + 1 + 1) :=
  (loaded3Environment leading spelling trailing first second third).push
    (.signed .i32 fourth)

def loaded5Environment (leading spelling trailing : List Int)
    (first second third fourth fifth : Int) : Env (4 + 1 + 1 + 1 + 1 + 1) :=
  (loaded4Environment leading spelling trailing first second third fourth).push
    (.signed .i32 fifth)

def loaded6Environment (leading spelling trailing : List Int)
    (first second third fourth fifth sixth : Int) : Env (4 + 1 + 1 + 1 + 1 + 1 + 1) :=
  (loaded5Environment leading spelling trailing first second third fourth fifth).push
    (.signed .i32 sixth)

def loaded7Environment (leading spelling trailing : List Int)
    (first second third fourth fifth sixth seventh : Int) : Env (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1) :=
  (loaded6Environment leading spelling trailing first second third fourth fifth sixth).push
    (.signed .i32 seventh)

def loaded8Environment (leading spelling trailing : List Int)
    (first second third fourth fifth sixth seventh eighth : Int) : Env (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1) :=
  (loaded7Environment leading spelling trailing first second third fourth fifth sixth seventh).push
    (.signed .i32 eighth)


@[simp] theorem loaded2Environment_four
    (leading spelling trailing : List Int) (first second : Int) :
    loaded2Environment leading spelling trailing first second
        ⟨4, by omega⟩ = .signed .i32 first := by
  unfold loaded2Environment loaded1Environment
  rw [Env.push_of_lt _ _ _ (by decide), Env.push_last]

@[simp] theorem loaded2Environment_five
    (leading spelling trailing : List Int) (first second : Int) :
    loaded2Environment leading spelling trailing first second
        ⟨5, by omega⟩ = .signed .i32 second := by
  unfold loaded2Environment loaded1Environment
  rw [Env.push_last]

theorem loaded2Environment_at_four
    (leading spelling trailing : List Int) (first second : Int)
    (position : Fin (4 + 1 + 1)) (same : position.val = 4) :
    loaded2Environment leading spelling trailing first second position =
      .signed .i32 first := by
  have positionEq : position = ⟨4, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded2Environment_four leading spelling trailing first second

theorem loaded2Environment_at_five
    (leading spelling trailing : List Int) (first second : Int)
    (position : Fin (4 + 1 + 1)) (same : position.val = 5) :
    loaded2Environment leading spelling trailing first second position =
      .signed .i32 second := by
  have positionEq : position = ⟨5, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded2Environment_five leading spelling trailing first second

@[simp] theorem loaded3Environment_four
    (leading spelling trailing : List Int) (first second third : Int) :
    loaded3Environment leading spelling trailing first second third
        ⟨4, by omega⟩ = .signed .i32 first := by
  unfold loaded3Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded2Environment_four]

@[simp] theorem loaded3Environment_five
    (leading spelling trailing : List Int) (first second third : Int) :
    loaded3Environment leading spelling trailing first second third
        ⟨5, by omega⟩ = .signed .i32 second := by
  unfold loaded3Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded2Environment_five]

@[simp] theorem loaded3Environment_six
    (leading spelling trailing : List Int) (first second third : Int) :
    loaded3Environment leading spelling trailing first second third
        ⟨6, by omega⟩ = .signed .i32 third := by
  unfold loaded3Environment
  rw [Env.push_last]

@[simp] theorem loaded4Environment_four
    (leading spelling trailing : List Int) (first second third fourth : Int) :
    loaded4Environment leading spelling trailing first second third fourth
        ⟨4, by omega⟩ = .signed .i32 first := by
  unfold loaded4Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded3Environment_four]

@[simp] theorem loaded4Environment_five
    (leading spelling trailing : List Int) (first second third fourth : Int) :
    loaded4Environment leading spelling trailing first second third fourth
        ⟨5, by omega⟩ = .signed .i32 second := by
  unfold loaded4Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded3Environment_five]

@[simp] theorem loaded4Environment_six
    (leading spelling trailing : List Int) (first second third fourth : Int) :
    loaded4Environment leading spelling trailing first second third fourth
        ⟨6, by omega⟩ = .signed .i32 third := by
  unfold loaded4Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded3Environment_six]

@[simp] theorem loaded4Environment_seven
    (leading spelling trailing : List Int) (first second third fourth : Int) :
    loaded4Environment leading spelling trailing first second third fourth
        ⟨7, by omega⟩ = .signed .i32 fourth := by
  unfold loaded4Environment
  rw [Env.push_last]

@[simp] theorem loaded5Environment_four
    (leading spelling trailing : List Int) (first second third fourth fifth : Int) :
    loaded5Environment leading spelling trailing first second third fourth fifth
        ⟨4, by omega⟩ = .signed .i32 first := by
  unfold loaded5Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded4Environment_four]

@[simp] theorem loaded5Environment_five
    (leading spelling trailing : List Int) (first second third fourth fifth : Int) :
    loaded5Environment leading spelling trailing first second third fourth fifth
        ⟨5, by omega⟩ = .signed .i32 second := by
  unfold loaded5Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded4Environment_five]

@[simp] theorem loaded5Environment_six
    (leading spelling trailing : List Int) (first second third fourth fifth : Int) :
    loaded5Environment leading spelling trailing first second third fourth fifth
        ⟨6, by omega⟩ = .signed .i32 third := by
  unfold loaded5Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded4Environment_six]

@[simp] theorem loaded5Environment_seven
    (leading spelling trailing : List Int) (first second third fourth fifth : Int) :
    loaded5Environment leading spelling trailing first second third fourth fifth
        ⟨7, by omega⟩ = .signed .i32 fourth := by
  unfold loaded5Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded4Environment_seven]

@[simp] theorem loaded5Environment_eight
    (leading spelling trailing : List Int) (first second third fourth fifth : Int) :
    loaded5Environment leading spelling trailing first second third fourth fifth
        ⟨8, by omega⟩ = .signed .i32 fifth := by
  unfold loaded5Environment
  rw [Env.push_last]

@[simp] theorem loaded6Environment_four
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth
        ⟨4, by omega⟩ = .signed .i32 first := by
  unfold loaded6Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded5Environment_four]

@[simp] theorem loaded6Environment_five
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth
        ⟨5, by omega⟩ = .signed .i32 second := by
  unfold loaded6Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded5Environment_five]

@[simp] theorem loaded6Environment_six
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth
        ⟨6, by omega⟩ = .signed .i32 third := by
  unfold loaded6Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded5Environment_six]

@[simp] theorem loaded6Environment_seven
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth
        ⟨7, by omega⟩ = .signed .i32 fourth := by
  unfold loaded6Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded5Environment_seven]

@[simp] theorem loaded6Environment_eight
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth
        ⟨8, by omega⟩ = .signed .i32 fifth := by
  unfold loaded6Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded5Environment_eight]

@[simp] theorem loaded6Environment_nine
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth
        ⟨9, by omega⟩ = .signed .i32 sixth := by
  unfold loaded6Environment
  rw [Env.push_last]

@[simp] theorem loaded7Environment_four
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh : Int) :
    loaded7Environment leading spelling trailing first second third fourth fifth sixth seventh
        ⟨4, by omega⟩ = .signed .i32 first := by
  unfold loaded7Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded6Environment_four]

@[simp] theorem loaded7Environment_five
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh : Int) :
    loaded7Environment leading spelling trailing first second third fourth fifth sixth seventh
        ⟨5, by omega⟩ = .signed .i32 second := by
  unfold loaded7Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded6Environment_five]

@[simp] theorem loaded7Environment_six
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh : Int) :
    loaded7Environment leading spelling trailing first second third fourth fifth sixth seventh
        ⟨6, by omega⟩ = .signed .i32 third := by
  unfold loaded7Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded6Environment_six]

@[simp] theorem loaded7Environment_seven
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh : Int) :
    loaded7Environment leading spelling trailing first second third fourth fifth sixth seventh
        ⟨7, by omega⟩ = .signed .i32 fourth := by
  unfold loaded7Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded6Environment_seven]

@[simp] theorem loaded7Environment_eight
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh : Int) :
    loaded7Environment leading spelling trailing first second third fourth fifth sixth seventh
        ⟨8, by omega⟩ = .signed .i32 fifth := by
  unfold loaded7Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded6Environment_eight]

@[simp] theorem loaded7Environment_nine
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh : Int) :
    loaded7Environment leading spelling trailing first second third fourth fifth sixth seventh
        ⟨9, by omega⟩ = .signed .i32 sixth := by
  unfold loaded7Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded6Environment_nine]

@[simp] theorem loaded7Environment_ten
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh : Int) :
    loaded7Environment leading spelling trailing first second third fourth fifth sixth seventh
        ⟨10, by omega⟩ = .signed .i32 seventh := by
  unfold loaded7Environment
  rw [Env.push_last]

@[simp] theorem loaded8Environment_four
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth
        ⟨4, by omega⟩ = .signed .i32 first := by
  unfold loaded8Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded7Environment_four]

@[simp] theorem loaded8Environment_five
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth
        ⟨5, by omega⟩ = .signed .i32 second := by
  unfold loaded8Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded7Environment_five]

@[simp] theorem loaded8Environment_six
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth
        ⟨6, by omega⟩ = .signed .i32 third := by
  unfold loaded8Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded7Environment_six]

@[simp] theorem loaded8Environment_seven
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth
        ⟨7, by omega⟩ = .signed .i32 fourth := by
  unfold loaded8Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded7Environment_seven]

@[simp] theorem loaded8Environment_eight
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth
        ⟨8, by omega⟩ = .signed .i32 fifth := by
  unfold loaded8Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded7Environment_eight]

@[simp] theorem loaded8Environment_nine
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth
        ⟨9, by omega⟩ = .signed .i32 sixth := by
  unfold loaded8Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded7Environment_nine]

@[simp] theorem loaded8Environment_ten
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth
        ⟨10, by omega⟩ = .signed .i32 seventh := by
  unfold loaded8Environment
  rw [Env.push_of_lt _ _ _ (by decide), loaded7Environment_ten]

@[simp] theorem loaded8Environment_eleven
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth
        ⟨11, by omega⟩ = .signed .i32 eighth := by
  unfold loaded8Environment
  rw [Env.push_last]


theorem loaded3Environment_at_four
    (leading spelling trailing : List Int) (first second third : Int)
    (position : Fin (4 + 1 + 1 + 1)) (same : position.val = 4) :
    loaded3Environment leading spelling trailing first second third position =
      .signed .i32 first := by
  have positionEq : position = ⟨4, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded3Environment_four leading spelling trailing first second third

theorem loaded3Environment_at_five
    (leading spelling trailing : List Int) (first second third : Int)
    (position : Fin (4 + 1 + 1 + 1)) (same : position.val = 5) :
    loaded3Environment leading spelling trailing first second third position =
      .signed .i32 second := by
  have positionEq : position = ⟨5, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded3Environment_five leading spelling trailing first second third

theorem loaded3Environment_at_six
    (leading spelling trailing : List Int) (first second third : Int)
    (position : Fin (4 + 1 + 1 + 1)) (same : position.val = 6) :
    loaded3Environment leading spelling trailing first second third position =
      .signed .i32 third := by
  have positionEq : position = ⟨6, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded3Environment_six leading spelling trailing first second third

theorem loaded4Environment_at_four
    (leading spelling trailing : List Int) (first second third fourth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1)) (same : position.val = 4) :
    loaded4Environment leading spelling trailing first second third fourth position =
      .signed .i32 first := by
  have positionEq : position = ⟨4, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded4Environment_four leading spelling trailing first second third fourth

theorem loaded4Environment_at_five
    (leading spelling trailing : List Int) (first second third fourth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1)) (same : position.val = 5) :
    loaded4Environment leading spelling trailing first second third fourth position =
      .signed .i32 second := by
  have positionEq : position = ⟨5, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded4Environment_five leading spelling trailing first second third fourth

theorem loaded4Environment_at_six
    (leading spelling trailing : List Int) (first second third fourth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1)) (same : position.val = 6) :
    loaded4Environment leading spelling trailing first second third fourth position =
      .signed .i32 third := by
  have positionEq : position = ⟨6, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded4Environment_six leading spelling trailing first second third fourth

theorem loaded4Environment_at_seven
    (leading spelling trailing : List Int) (first second third fourth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1)) (same : position.val = 7) :
    loaded4Environment leading spelling trailing first second third fourth position =
      .signed .i32 fourth := by
  have positionEq : position = ⟨7, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded4Environment_seven leading spelling trailing first second third fourth

theorem loaded5Environment_at_four
    (leading spelling trailing : List Int) (first second third fourth fifth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 4) :
    loaded5Environment leading spelling trailing first second third fourth fifth position =
      .signed .i32 first := by
  have positionEq : position = ⟨4, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded5Environment_four leading spelling trailing first second third fourth fifth

theorem loaded5Environment_at_five
    (leading spelling trailing : List Int) (first second third fourth fifth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 5) :
    loaded5Environment leading spelling trailing first second third fourth fifth position =
      .signed .i32 second := by
  have positionEq : position = ⟨5, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded5Environment_five leading spelling trailing first second third fourth fifth

theorem loaded5Environment_at_six
    (leading spelling trailing : List Int) (first second third fourth fifth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 6) :
    loaded5Environment leading spelling trailing first second third fourth fifth position =
      .signed .i32 third := by
  have positionEq : position = ⟨6, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded5Environment_six leading spelling trailing first second third fourth fifth

theorem loaded5Environment_at_seven
    (leading spelling trailing : List Int) (first second third fourth fifth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 7) :
    loaded5Environment leading spelling trailing first second third fourth fifth position =
      .signed .i32 fourth := by
  have positionEq : position = ⟨7, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded5Environment_seven leading spelling trailing first second third fourth fifth

theorem loaded5Environment_at_eight
    (leading spelling trailing : List Int) (first second third fourth fifth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 8) :
    loaded5Environment leading spelling trailing first second third fourth fifth position =
      .signed .i32 fifth := by
  have positionEq : position = ⟨8, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded5Environment_eight leading spelling trailing first second third fourth fifth

theorem loaded6Environment_at_four
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 4) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth position =
      .signed .i32 first := by
  have positionEq : position = ⟨4, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded6Environment_four leading spelling trailing first second third fourth fifth sixth

theorem loaded6Environment_at_five
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 5) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth position =
      .signed .i32 second := by
  have positionEq : position = ⟨5, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded6Environment_five leading spelling trailing first second third fourth fifth sixth

theorem loaded6Environment_at_six
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 6) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth position =
      .signed .i32 third := by
  have positionEq : position = ⟨6, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded6Environment_six leading spelling trailing first second third fourth fifth sixth

theorem loaded6Environment_at_seven
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 7) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth position =
      .signed .i32 fourth := by
  have positionEq : position = ⟨7, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded6Environment_seven leading spelling trailing first second third fourth fifth sixth

theorem loaded6Environment_at_eight
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 8) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth position =
      .signed .i32 fifth := by
  have positionEq : position = ⟨8, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded6Environment_eight leading spelling trailing first second third fourth fifth sixth

theorem loaded6Environment_at_nine
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 9) :
    loaded6Environment leading spelling trailing first second third fourth fifth sixth position =
      .signed .i32 sixth := by
  have positionEq : position = ⟨9, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded6Environment_nine leading spelling trailing first second third fourth fifth sixth

theorem loaded8Environment_at_four
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 4) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth position =
      .signed .i32 first := by
  have positionEq : position = ⟨4, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded8Environment_four leading spelling trailing first second third fourth fifth sixth seventh eighth

theorem loaded8Environment_at_five
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 5) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth position =
      .signed .i32 second := by
  have positionEq : position = ⟨5, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded8Environment_five leading spelling trailing first second third fourth fifth sixth seventh eighth

theorem loaded8Environment_at_six
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 6) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth position =
      .signed .i32 third := by
  have positionEq : position = ⟨6, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded8Environment_six leading spelling trailing first second third fourth fifth sixth seventh eighth

theorem loaded8Environment_at_seven
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 7) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth position =
      .signed .i32 fourth := by
  have positionEq : position = ⟨7, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded8Environment_seven leading spelling trailing first second third fourth fifth sixth seventh eighth

theorem loaded8Environment_at_eight
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 8) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth position =
      .signed .i32 fifth := by
  have positionEq : position = ⟨8, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded8Environment_eight leading spelling trailing first second third fourth fifth sixth seventh eighth

theorem loaded8Environment_at_nine
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 9) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth position =
      .signed .i32 sixth := by
  have positionEq : position = ⟨9, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded8Environment_nine leading spelling trailing first second third fourth fifth sixth seventh eighth

theorem loaded8Environment_at_ten
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 10) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth position =
      .signed .i32 seventh := by
  have positionEq : position = ⟨10, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded8Environment_ten leading spelling trailing first second third fourth fifth sixth seventh eighth

theorem loaded8Environment_at_eleven
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int)
    (position : Fin (4 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1)) (same : position.val = 11) :
    loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth position =
      .signed .i32 eighth := by
  have positionEq : position = ⟨11, by omega⟩ := Fin.ext same
  rw [positionEq]
  exact loaded8Environment_eleven leading spelling trailing first second third fourth fifth sixth seventh eighth


theorem directLoad2_evaluates_of_body
    (leading spelling trailing : List Int)
    (first second : Int)
    (body : KeywordCommand.C 6) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (loaded2Environment leading spelling trailing first second) body =
        some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
          loaded2Environment leading spelling trailing first second)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (lengthEnvironment leading spelling trailing)
        (KeywordCommand.directLoad2 body) =
      some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  have firstIndex := evaluate_embedded_directIndex_zero
    leading [first, second] trailing
    (lengthEnvironment leading [first, second] trailing) 0 1
    (by simp)
    (by simp [lengthEnvironment, Model.keywordEnvironment])
    (by simp [lengthEnvironment, Model.keywordEnvironment])
  have secondBound : leading.length + 1 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have secondIndex := evaluate_embedded_directIndex
    leading [first, second] trailing
    ((lengthEnvironment leading [first, second] trailing).push
      (.signed .i32 first)) 0 1 1 (by simp)
    (by simp [lengthEnvironment, Model.keywordEnvironment])
    (by simp [lengthEnvironment, Model.keywordEnvironment]) secondBound
  have firstIndex' : Term.evaluate TM
      (Model.keywordWorld (leading ++ [first, second] ++ trailing))
      (lengthEnvironment leading [first, second] trailing)
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directSlot 1)) =
    .ok (.signed .i32 first,
      Model.keywordWorld (leading ++ [first, second] ++ trailing)) := by
    simpa using firstIndex
  have secondIndex' : Term.evaluate TM
      (Model.keywordWorld (leading ++ [first, second] ++ trailing))
      ((lengthEnvironment leading [first, second] trailing).push
        (.signed .i32 first))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 1))) =
    .ok (.signed .i32 second,
      Model.keywordWorld (leading ++ [first, second] ++ trailing)) := by
    simpa using secondIndex
  simp only [KeywordCommand.directLoad2,
    Lanius.FunctionalView.Stateful.Acyclic.run?]
  rw [firstIndex']
  simp only
  rw [secondIndex']
  simp only
  have environmentEq :
      ((lengthEnvironment leading [first, second] trailing).push
        (.signed .i32 first)).push (.signed .i32 second) =
      loaded2Environment leading [first, second] trailing first second := by
    rfl
  rw [environmentEq]
  have choices' : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ [first, second] ++ trailing))
      (loaded2Environment leading [first, second] trailing first second)
      body =
    some (completion, Model.keywordWorld (leading ++ [first, second] ++ trailing),
      loaded2Environment leading [first, second] trailing first second) := by
    exact bodyResult
  rw [choices']
  simp only [loaded2Environment, loaded1Environment,
    Stateful.Env.pop_push]
  rfl

theorem length2Rules_loaded
    (leading trailing : List Int) (first second : Int) :
    ∀ bytes constant,
      (bytes, constant) ∈ KeywordCommand.length2Rules →
        ∀ position expected, (position, expected) ∈ bytes →
          ∃ actual,
            loaded2Environment leading [first, second] trailing first second
              position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length2Rules] at member
  rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp at byteMember <;>
    rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    first
    | exact ⟨first, loaded2Environment_four
        leading [first, second] trailing first second⟩
    | exact ⟨second, loaded2Environment_five
        leading [first, second] trailing first second⟩

theorem directLoad2_noMatch_evaluates
    (leading spelling trailing : List Int)
    (first second : Int)
    (spellingShape : spelling = [first, second])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (noMatch : KeywordLengthSemantics.firstMatchingConstant
      (loaded2Environment leading spelling trailing first second)
      KeywordCommand.length2Rules = none) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (lengthEnvironment leading spelling trailing)
        (KeywordCommand.directLoad2
          (KeywordCommand.directChoices KeywordCommand.length2Rules)) =
      some (.next, Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad2_evaluates_of_body leading [first, second] trailing
    first second _ .next rfl bounded
  exact KeywordLengthSemantics.directChoices_noMatch_evaluates
    (environment := loaded2Environment leading [first, second] trailing
      first second)
    (rules := KeywordCommand.length2Rules)
    (length2Rules_loaded leading trailing first second) noMatch

theorem directLoad2_match_evaluates
    (leading spelling trailing : List Int)
    (first second : Int) (constant : ConstantId) (declaration : Constant)
    (spellingShape : spelling = [first, second])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (selected : KeywordLengthSemantics.firstMatchingConstant
      (loaded2Environment leading spelling trailing first second)
      KeywordCommand.length2Rules = some constant)
    (found : verifiedFrontendCore.constant? constant = some declaration) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (lengthEnvironment leading spelling trailing)
        (KeywordCommand.directLoad2
          (KeywordCommand.directChoices KeywordCommand.length2Rules)) =
      some (.returned (some declaration.value),
        Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad2_evaluates_of_body leading [first, second] trailing
    first second _ (.returned (some declaration.value)) rfl bounded
  exact KeywordLengthSemantics.directChoices_match_evaluates
    (environment := loaded2Environment leading [first, second] trailing
      first second)
    (rules := KeywordCommand.length2Rules)
    (length2Rules_loaded leading trailing first second)
    selected declaration found

theorem directLoad3_evaluates_of_body
    (leading spelling trailing : List Int)
    (first second third : Int)
    (body : KeywordCommand.C 7) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second, third])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (loaded3Environment leading spelling trailing first second third) body =
        some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
          loaded3Environment leading spelling trailing first second third)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (lengthEnvironment leading spelling trailing)
        (KeywordCommand.directLoad3 body) =
      some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  let world := Model.keywordWorld (leading ++ [first, second, third] ++ trailing)
  let base := lengthEnvironment leading [first, second, third] trailing
  have firstIndex : Term.evaluate TM world base
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directSlot 1)) =
    .ok (.signed .i32 first, world) := by
    simpa [world, base] using evaluate_embedded_directIndex_zero
      leading [first, second, third] trailing base 0 1 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
  have firstBound : leading.length + 1 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have secondIndex : Term.evaluate TM world
      (base.push (.signed .i32 first))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 1))) =
    .ok (.signed .i32 second, world) := by
    simpa [world, base] using evaluate_embedded_directIndex
      leading [first, second, third] trailing
      (base.push (.signed .i32 first)) 0 1 1 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) firstBound
  have secondBound : leading.length + 2 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have thirdIndex : Term.evaluate TM world
      ((base.push (.signed .i32 first)).push (.signed .i32 second))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 2))) =
    .ok (.signed .i32 third, world) := by
    simpa [world, base] using evaluate_embedded_directIndex
      leading [first, second, third] trailing
      ((base.push (.signed .i32 first)).push (.signed .i32 second))
      0 1 2 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) secondBound
  unfold KeywordCommand.directLoad3
  apply run_letValue_preserving world base KeywordCommand.i32 _ _
    (.signed .i32 first) completion firstIndex
  apply run_letValue_preserving world (base.push (.signed .i32 first))
    KeywordCommand.i32 _ _ (.signed .i32 second) completion secondIndex
  apply run_letValue_preserving world
    ((base.push (.signed .i32 first)).push (.signed .i32 second))
    KeywordCommand.i32 _ _ (.signed .i32 third) completion thirdIndex
  simpa [world, base, loaded3Environment, loaded2Environment,
    loaded1Environment] using bodyResult

theorem length3Rules_loaded
    (leading trailing : List Int) (first second third : Int) :
    ∀ bytes constant,
      (bytes, constant) ∈ KeywordCommand.length3Rules →
        ∀ position expected, (position, expected) ∈ bytes →
          ∃ actual,
            loaded3Environment leading [first, second, third] trailing
              first second third position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length3Rules] at member
  rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp at byteMember <;>
    rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    first
    | exact ⟨first, loaded3Environment_four
        leading [first, second, third] trailing first second third⟩
    | exact ⟨second, loaded3Environment_five
        leading [first, second, third] trailing first second third⟩
    | exact ⟨third, loaded3Environment_six
        leading [first, second, third] trailing first second third⟩

theorem directLoad3_noMatch_evaluates
    (leading spelling trailing : List Int)
    (first second third : Int)
    (spellingShape : spelling = [first, second, third])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (noMatch : KeywordLengthSemantics.firstMatchingConstant
      (loaded3Environment leading spelling trailing first second third)
      KeywordCommand.length3Rules = none) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (lengthEnvironment leading spelling trailing)
        (KeywordCommand.directLoad3
          (KeywordCommand.directChoices KeywordCommand.length3Rules)) =
      some (.next, Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad3_evaluates_of_body leading [first, second, third] trailing
    first second third _ .next rfl bounded
  exact KeywordLengthSemantics.directChoices_noMatch_evaluates
    (environment := loaded3Environment leading [first, second, third] trailing
      first second third)
    (rules := KeywordCommand.length3Rules)
    (length3Rules_loaded leading trailing first second third) noMatch

theorem directLoad3_match_evaluates
    (leading spelling trailing : List Int)
    (first second third : Int) (constant : ConstantId)
    (declaration : Constant)
    (spellingShape : spelling = [first, second, third])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (selected : KeywordLengthSemantics.firstMatchingConstant
      (loaded3Environment leading spelling trailing first second third)
      KeywordCommand.length3Rules = some constant)
    (found : verifiedFrontendCore.constant? constant = some declaration) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (lengthEnvironment leading spelling trailing)
        (KeywordCommand.directLoad3
          (KeywordCommand.directChoices KeywordCommand.length3Rules)) =
      some (.returned (some declaration.value),
        Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad3_evaluates_of_body leading [first, second, third] trailing
    first second third _ (.returned (some declaration.value)) rfl bounded
  exact KeywordLengthSemantics.directChoices_match_evaluates
    (environment := loaded3Environment leading [first, second, third] trailing
      first second third)
    (rules := KeywordCommand.length3Rules)
    (length3Rules_loaded leading trailing first second third)
    selected declaration found

theorem directLoad4_evaluates_of_body
    (leading spelling trailing : List Int)
    (first second third fourth : Int)
    (body : KeywordCommand.C 8) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second, third, fourth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (loaded4Environment leading spelling trailing first second third fourth)
      body = some (completion,
        Model.keywordWorld (leading ++ spelling ++ trailing),
        loaded4Environment leading spelling trailing first second third fourth)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (lengthEnvironment leading spelling trailing)
        (KeywordCommand.directLoad4 body) =
      some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  let world := Model.keywordWorld
    (leading ++ [first, second, third, fourth] ++ trailing)
  let base := lengthEnvironment leading [first, second, third, fourth] trailing
  have index0 : Term.evaluate TM world base
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directSlot 1)) =
    .ok (.signed .i32 first, world) := by
    simpa [world, base] using evaluate_embedded_directIndex_zero
      leading [first, second, third, fourth] trailing base 0 1 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
  have bound1 : leading.length + 1 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index1 : Term.evaluate TM world
      (base.push (.signed .i32 first))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 1))) =
    .ok (.signed .i32 second, world) := by
    simpa [world, base] using evaluate_embedded_directIndex
      leading [first, second, third, fourth] trailing
      (base.push (.signed .i32 first)) 0 1 1 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound1
  have bound2 : leading.length + 2 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index2 : Term.evaluate TM world
      ((base.push (.signed .i32 first)).push (.signed .i32 second))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 2))) =
    .ok (.signed .i32 third, world) := by
    simpa [world, base] using evaluate_embedded_directIndex
      leading [first, second, third, fourth] trailing
      ((base.push (.signed .i32 first)).push (.signed .i32 second))
      0 1 2 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound2
  have bound3 : leading.length + 3 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index3 : Term.evaluate TM world
      (((base.push (.signed .i32 first)).push (.signed .i32 second)).push
        (.signed .i32 third))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 3))) =
    .ok (.signed .i32 fourth, world) := by
    have evaluated := evaluate_embedded_directIndex
      leading [first, second, third, fourth] trailing
      (((base.push (.signed .i32 first)).push (.signed .i32 second)).push
        (.signed .i32 third)) 0 1 3 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound3
    have valueEq : [first, second, third, fourth].get
        ⟨3, by simp⟩ = fourth := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  unfold KeywordCommand.directLoad4
  apply run_letValue_preserving world base KeywordCommand.i32 _ _
    (.signed .i32 first) completion index0
  apply run_letValue_preserving world (base.push (.signed .i32 first))
    KeywordCommand.i32 _ _ (.signed .i32 second) completion index1
  apply run_letValue_preserving world
    ((base.push (.signed .i32 first)).push (.signed .i32 second))
    KeywordCommand.i32 _ _ (.signed .i32 third) completion index2
  apply run_letValue_preserving world
    (((base.push (.signed .i32 first)).push (.signed .i32 second)).push
      (.signed .i32 third)) KeywordCommand.i32 _ _
    (.signed .i32 fourth) completion index3
  simpa [world, base, loaded4Environment, loaded3Environment,
    loaded2Environment, loaded1Environment] using bodyResult

theorem length4Rules_loaded
    (leading trailing : List Int) (first second third fourth : Int) :
    ∀ bytes constant,
      (bytes, constant) ∈ KeywordCommand.length4Rules →
        ∀ position expected, (position, expected) ∈ bytes →
          ∃ actual, loaded4Environment leading
            [first, second, third, fourth] trailing first second third fourth
              position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length4Rules] at member
  rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
      ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp at byteMember <;>
    rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
      ⟨rfl, rfl⟩ <;>
    first
    | exact ⟨first, loaded4Environment_four leading
        [first, second, third, fourth] trailing first second third fourth⟩
    | exact ⟨second, loaded4Environment_five leading
        [first, second, third, fourth] trailing first second third fourth⟩
    | exact ⟨third, loaded4Environment_six leading
        [first, second, third, fourth] trailing first second third fourth⟩
    | exact ⟨fourth, loaded4Environment_seven leading
        [first, second, third, fourth] trailing first second third fourth⟩

theorem directLoad4_noMatch_evaluates
    (leading spelling trailing : List Int)
    (first second third fourth : Int)
    (spellingShape : spelling = [first, second, third, fourth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (noMatch : KeywordLengthSemantics.firstMatchingConstant
      (loaded4Environment leading spelling trailing first second third fourth)
      KeywordCommand.length4Rules = none) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (lengthEnvironment leading spelling trailing)
        (KeywordCommand.directLoad4
          (KeywordCommand.directChoices KeywordCommand.length4Rules)) =
      some (.next, Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad4_evaluates_of_body leading
    [first, second, third, fourth] trailing first second third fourth _ .next
    rfl bounded
  exact KeywordLengthSemantics.directChoices_noMatch_evaluates
    (environment := loaded4Environment leading
      [first, second, third, fourth] trailing first second third fourth)
    (rules := KeywordCommand.length4Rules)
    (length4Rules_loaded leading trailing first second third fourth) noMatch

theorem directLoad4_match_evaluates
    (leading spelling trailing : List Int)
    (first second third fourth : Int) (constant : ConstantId)
    (declaration : Constant)
    (spellingShape : spelling = [first, second, third, fourth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (selected : KeywordLengthSemantics.firstMatchingConstant
      (loaded4Environment leading spelling trailing first second third fourth)
      KeywordCommand.length4Rules = some constant)
    (found : verifiedFrontendCore.constant? constant = some declaration) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (Model.keywordWorld (leading ++ spelling ++ trailing))
        (lengthEnvironment leading spelling trailing)
        (KeywordCommand.directLoad4
          (KeywordCommand.directChoices KeywordCommand.length4Rules)) =
      some (.returned (some declaration.value),
        Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad4_evaluates_of_body leading
    [first, second, third, fourth] trailing first second third fourth _
    (.returned (some declaration.value)) rfl bounded
  exact KeywordLengthSemantics.directChoices_match_evaluates
    (environment := loaded4Environment leading
      [first, second, third, fourth] trailing first second third fourth)
    (rules := KeywordCommand.length4Rules)
    (length4Rules_loaded leading trailing first second third fourth)
    selected declaration found

theorem directLoad5_evaluates_of_body
    (leading spelling trailing : List Int)
    (first second third fourth fifth : Int)
    (body : KeywordCommand.C 9) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second, third, fourth, fifth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (loaded5Environment leading spelling trailing first second third fourth fifth) body =
        some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
          loaded5Environment leading spelling trailing first second third fourth fifth)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (lengthEnvironment leading spelling trailing)
      (KeywordCommand.directLoad5 body) =
        some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
          lengthEnvironment leading spelling trailing) := by
  subst spelling
  let world := Model.keywordWorld (leading ++ [first, second, third, fourth, fifth] ++ trailing)
  let base := lengthEnvironment leading [first, second, third, fourth, fifth] trailing
  have index0 : Term.evaluate TM world base
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directSlot 1)) =
    .ok (.signed .i32 first, world) := by
    simpa [world, base] using evaluate_embedded_directIndex_zero
      leading [first, second, third, fourth, fifth] trailing base 0 1 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
  have bound1 : leading.length + 1 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index1 : Term.evaluate TM world
      (base.push (.signed .i32 first))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 1))) =
    .ok (.signed .i32 second, world) := by
    have evaluated := evaluate_embedded_directIndex
      leading [first, second, third, fourth, fifth] trailing (base.push (.signed .i32 first)) 0 1 1 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound1
    simpa [world, base] using evaluated
  have bound2 : leading.length + 2 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index2 : Term.evaluate TM world
      ((base.push (.signed .i32 first)).push (.signed .i32 second))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 2))) =
    .ok (.signed .i32 third, world) := by
    have evaluated := evaluate_embedded_directIndex
      leading [first, second, third, fourth, fifth] trailing ((base.push (.signed .i32 first)).push (.signed .i32 second)) 0 1 2 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound2
    simpa [world, base] using evaluated
  have bound3 : leading.length + 3 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index3 : Term.evaluate TM world
      (((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 3))) =
    .ok (.signed .i32 fourth, world) := by
    have evaluated := evaluate_embedded_directIndex
      leading [first, second, third, fourth, fifth] trailing (((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)) 0 1 3 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound3
    have valueEq : [first, second, third, fourth, fifth].get ⟨3, by simp⟩ = fourth := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  have bound4 : leading.length + 4 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index4 : Term.evaluate TM world
      ((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 4))) =
    .ok (.signed .i32 fifth, world) := by
    have evaluated := evaluate_embedded_directIndex
      leading [first, second, third, fourth, fifth] trailing ((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)) 0 1 4 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound4
    have valueEq : [first, second, third, fourth, fifth].get ⟨4, by simp⟩ = fifth := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  unfold KeywordCommand.directLoad5
  apply run_letValue_preserving world base KeywordCommand.i32 _ _
    (.signed .i32 first) completion index0
  apply run_letValue_preserving world (base.push (.signed .i32 first)) KeywordCommand.i32 _ _
    (.signed .i32 second) completion index1
  apply run_letValue_preserving world ((base.push (.signed .i32 first)).push (.signed .i32 second)) KeywordCommand.i32 _ _
    (.signed .i32 third) completion index2
  apply run_letValue_preserving world (((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)) KeywordCommand.i32 _ _
    (.signed .i32 fourth) completion index3
  apply run_letValue_preserving world ((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)) KeywordCommand.i32 _ _
    (.signed .i32 fifth) completion index4
  simpa [world, base, loaded5Environment, loaded4Environment, loaded3Environment, loaded2Environment, loaded1Environment] using bodyResult


theorem length5Rules_loaded
    (leading trailing : List Int) (first second third fourth fifth : Int) :
    ∀ bytes constant, (bytes, constant) ∈ KeywordCommand.length5Rules →
      ∀ position expected, (position, expected) ∈ bytes →
        ∃ actual, loaded5Environment leading [first, second, third, fourth, fifth] trailing first second third fourth fifth
          position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length5Rules] at member
  rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp at byteMember <;>
    rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    first
    | exact ⟨first, loaded5Environment_four leading
        [first, second, third, fourth, fifth] trailing first second third fourth fifth⟩
    | exact ⟨second, loaded5Environment_five leading
        [first, second, third, fourth, fifth] trailing first second third fourth fifth⟩
    | exact ⟨third, loaded5Environment_six leading
        [first, second, third, fourth, fifth] trailing first second third fourth fifth⟩
    | exact ⟨fourth, loaded5Environment_seven leading
        [first, second, third, fourth, fifth] trailing first second third fourth fifth⟩
    | exact ⟨fifth, loaded5Environment_eight leading
        [first, second, third, fourth, fifth] trailing first second third fourth fifth⟩

theorem directLoad5_noMatch_evaluates
    (leading spelling trailing : List Int) (first second third fourth fifth : Int)
    (spellingShape : spelling = [first, second, third, fourth, fifth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (noMatch : KeywordLengthSemantics.firstMatchingConstant
      (loaded5Environment leading spelling trailing first second third fourth fifth)
      KeywordCommand.length5Rules = none) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (lengthEnvironment leading spelling trailing)
      (KeywordCommand.directLoad5
        (KeywordCommand.directChoices KeywordCommand.length5Rules)) =
      some (.next, Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad5_evaluates_of_body leading [first, second, third, fourth, fifth] trailing first second third fourth fifth
    _ .next rfl bounded
  exact KeywordLengthSemantics.directChoices_noMatch_evaluates
    (environment := loaded5Environment leading [first, second, third, fourth, fifth] trailing first second third fourth fifth)
    (rules := KeywordCommand.length5Rules)
    (length5Rules_loaded leading trailing first second third fourth fifth) noMatch

theorem directLoad5_match_evaluates
    (leading spelling trailing : List Int) (first second third fourth fifth : Int)
    (constant : ConstantId) (declaration : Constant)
    (spellingShape : spelling = [first, second, third, fourth, fifth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (selected : KeywordLengthSemantics.firstMatchingConstant
      (loaded5Environment leading spelling trailing first second third fourth fifth)
      KeywordCommand.length5Rules = some constant)
    (found : verifiedFrontendCore.constant? constant = some declaration) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (lengthEnvironment leading spelling trailing)
      (KeywordCommand.directLoad5
        (KeywordCommand.directChoices KeywordCommand.length5Rules)) =
      some (.returned (some declaration.value),
        Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad5_evaluates_of_body leading [first, second, third, fourth, fifth] trailing first second third fourth fifth
    _ (.returned (some declaration.value)) rfl bounded
  exact KeywordLengthSemantics.directChoices_match_evaluates
    (environment := loaded5Environment leading [first, second, third, fourth, fifth] trailing first second third fourth fifth)
    (rules := KeywordCommand.length5Rules)
    (length5Rules_loaded leading trailing first second third fourth fifth)
    selected declaration found


theorem directLoad6_evaluates_of_body
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int)
    (body : KeywordCommand.C 10) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second, third, fourth, fifth, sixth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (loaded6Environment leading spelling trailing first second third fourth fifth sixth) body =
      some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
        loaded6Environment leading spelling trailing first second third fourth fifth sixth)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (lengthEnvironment leading spelling trailing) (KeywordCommand.directLoad6 body) =
      some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  let world := Model.keywordWorld (leading ++ [first, second, third, fourth, fifth, sixth] ++ trailing)
  let base := lengthEnvironment leading [first, second, third, fourth, fifth, sixth] trailing
  have index0 : Term.evaluate TM world base
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0) (KeywordCommand.directSlot 1)) =
      .ok (.signed .i32 first, world) := by
    simpa [world, base] using evaluate_embedded_directIndex_zero
      leading [first, second, third, fourth, fifth, sixth] trailing base 0 1 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
  have bound1 : leading.length + 1 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index1 : Term.evaluate TM world (base.push (.signed .i32 first))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 1))) =
      .ok (.signed .i32 second, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth] trailing
      (base.push (.signed .i32 first)) 0 1 1 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound1
    simpa [world, base] using evaluated
  have bound2 : leading.length + 2 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index2 : Term.evaluate TM world ((base.push (.signed .i32 first)).push (.signed .i32 second))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 2))) =
      .ok (.signed .i32 third, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth] trailing
      ((base.push (.signed .i32 first)).push (.signed .i32 second)) 0 1 2 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound2
    simpa [world, base] using evaluated
  have bound3 : leading.length + 3 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index3 : Term.evaluate TM world (((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 3))) =
      .ok (.signed .i32 fourth, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth] trailing
      (((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)) 0 1 3 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound3
    have valueEq : [first, second, third, fourth, fifth, sixth].get ⟨3, by simp⟩ = fourth := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  have bound4 : leading.length + 4 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index4 : Term.evaluate TM world ((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 4))) =
      .ok (.signed .i32 fifth, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth] trailing
      ((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)) 0 1 4 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound4
    have valueEq : [first, second, third, fourth, fifth, sixth].get ⟨4, by simp⟩ = fifth := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  have bound5 : leading.length + 5 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index5 : Term.evaluate TM world (((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 5))) =
      .ok (.signed .i32 sixth, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth] trailing
      (((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth)) 0 1 5 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound5
    have valueEq : [first, second, third, fourth, fifth, sixth].get ⟨5, by simp⟩ = sixth := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  unfold KeywordCommand.directLoad6
  apply run_letValue_preserving world base KeywordCommand.i32 _ _
    (.signed .i32 first) completion index0
  apply run_letValue_preserving world (base.push (.signed .i32 first)) KeywordCommand.i32 _ _
    (.signed .i32 second) completion index1
  apply run_letValue_preserving world ((base.push (.signed .i32 first)).push (.signed .i32 second)) KeywordCommand.i32 _ _
    (.signed .i32 third) completion index2
  apply run_letValue_preserving world (((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)) KeywordCommand.i32 _ _
    (.signed .i32 fourth) completion index3
  apply run_letValue_preserving world ((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)) KeywordCommand.i32 _ _
    (.signed .i32 fifth) completion index4
  apply run_letValue_preserving world (((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth)) KeywordCommand.i32 _ _
    (.signed .i32 sixth) completion index5
  simpa [world, base, loaded6Environment, loaded5Environment, loaded4Environment, loaded3Environment, loaded2Environment, loaded1Environment] using bodyResult

theorem length6Rules_loaded
    (leading trailing : List Int) (first second third fourth fifth sixth : Int) :
    ∀ bytes constant, (bytes, constant) ∈ KeywordCommand.length6Rules →
      ∀ position expected, (position, expected) ∈ bytes →
        ∃ actual, loaded6Environment leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth
          position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length6Rules] at member
  rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp at byteMember <;>
    rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    first
    | exact ⟨first, loaded6Environment_four leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth⟩
    | exact ⟨second, loaded6Environment_five leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth⟩
    | exact ⟨third, loaded6Environment_six leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth⟩
    | exact ⟨fourth, loaded6Environment_seven leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth⟩
    | exact ⟨fifth, loaded6Environment_eight leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth⟩
    | exact ⟨sixth, loaded6Environment_nine leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth⟩

theorem directLoad6_noMatch_evaluates
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int)
    (spellingShape : spelling = [first, second, third, fourth, fifth, sixth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (noMatch : KeywordLengthSemantics.firstMatchingConstant
      (loaded6Environment leading spelling trailing first second third fourth fifth sixth) KeywordCommand.length6Rules = none) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing)) (lengthEnvironment leading spelling trailing)
      (KeywordCommand.directLoad6 (KeywordCommand.directChoices KeywordCommand.length6Rules)) =
      some (.next, Model.keywordWorld (leading ++ spelling ++ trailing), lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad6_evaluates_of_body leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth _ .next rfl bounded
  exact KeywordLengthSemantics.directChoices_noMatch_evaluates
    (environment := loaded6Environment leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth)
    (rules := KeywordCommand.length6Rules) (length6Rules_loaded leading trailing first second third fourth fifth sixth) noMatch

theorem directLoad6_match_evaluates
    (leading spelling trailing : List Int) (first second third fourth fifth sixth : Int) (constant : ConstantId) (declaration : Constant)
    (spellingShape : spelling = [first, second, third, fourth, fifth, sixth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (selected : KeywordLengthSemantics.firstMatchingConstant
      (loaded6Environment leading spelling trailing first second third fourth fifth sixth) KeywordCommand.length6Rules = some constant)
    (found : verifiedFrontendCore.constant? constant = some declaration) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing)) (lengthEnvironment leading spelling trailing)
      (KeywordCommand.directLoad6 (KeywordCommand.directChoices KeywordCommand.length6Rules)) =
      some (.returned (some declaration.value), Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad6_evaluates_of_body leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth _
    (.returned (some declaration.value)) rfl bounded
  exact KeywordLengthSemantics.directChoices_match_evaluates
    (environment := loaded6Environment leading [first, second, third, fourth, fifth, sixth] trailing first second third fourth fifth sixth)
    (rules := KeywordCommand.length6Rules) (length6Rules_loaded leading trailing first second third fourth fifth sixth)
    selected declaration found


theorem directLoad8_evaluates_of_body
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int)
    (body : KeywordCommand.C 12) (completion : Stateful.Completion)
    (spellingShape : spelling = [first, second, third, fourth, fifth, sixth, seventh, eighth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth) body =
      some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
        loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth)) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (lengthEnvironment leading spelling trailing) (KeywordCommand.directLoad8 body) =
      some (completion, Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  let world := Model.keywordWorld (leading ++ [first, second, third, fourth, fifth, sixth, seventh, eighth] ++ trailing)
  let base := lengthEnvironment leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
  have index0 : Term.evaluate TM world base
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0) (KeywordCommand.directSlot 1)) =
      .ok (.signed .i32 first, world) := by
    simpa [world, base] using evaluate_embedded_directIndex_zero
      leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing base 0 1 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
  have bound1 : leading.length + 1 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index1 : Term.evaluate TM world (base.push (.signed .i32 first))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 1))) =
      .ok (.signed .i32 second, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
      (base.push (.signed .i32 first)) 0 1 1 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound1
    have valueEq : [first, second, third, fourth, fifth, sixth, seventh, eighth].get ⟨1, by simp⟩ = second := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  have bound2 : leading.length + 2 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index2 : Term.evaluate TM world ((base.push (.signed .i32 first)).push (.signed .i32 second))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 2))) =
      .ok (.signed .i32 third, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
      ((base.push (.signed .i32 first)).push (.signed .i32 second)) 0 1 2 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound2
    have valueEq : [first, second, third, fourth, fifth, sixth, seventh, eighth].get ⟨2, by simp⟩ = third := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  have bound3 : leading.length + 3 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index3 : Term.evaluate TM world (((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 3))) =
      .ok (.signed .i32 fourth, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
      (((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)) 0 1 3 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound3
    have valueEq : [first, second, third, fourth, fifth, sixth, seventh, eighth].get ⟨3, by simp⟩ = fourth := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  have bound4 : leading.length + 4 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index4 : Term.evaluate TM world ((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 4))) =
      .ok (.signed .i32 fifth, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
      ((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)) 0 1 4 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound4
    have valueEq : [first, second, third, fourth, fifth, sixth, seventh, eighth].get ⟨4, by simp⟩ = fifth := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  have bound5 : leading.length + 5 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index5 : Term.evaluate TM world (((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 5))) =
      .ok (.signed .i32 sixth, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
      (((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth)) 0 1 5 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound5
    have valueEq : [first, second, third, fourth, fifth, sixth, seventh, eighth].get ⟨5, by simp⟩ = sixth := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  have bound6 : leading.length + 6 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index6 : Term.evaluate TM world ((((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth)).push (.signed .i32 sixth))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 6))) =
      .ok (.signed .i32 seventh, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
      ((((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth)).push (.signed .i32 sixth)) 0 1 6 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound6
    have valueEq : [first, second, third, fourth, fifth, sixth, seventh, eighth].get ⟨6, by simp⟩ = seventh := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  have bound7 : leading.length + 7 ≤ 2147483647 := by
    simp only [List.length_append, List.length_cons, List.length_nil] at bounded
    omega
  have index7 : Term.evaluate TM world (((((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth)).push (.signed .i32 sixth)).push (.signed .i32 seventh))
      (KeywordCommand.directIndex (KeywordCommand.directSlot 0)
        (KeywordCommand.directAdd (KeywordCommand.directSlot 1)
          (KeywordCommand.directLiteral 7))) =
      .ok (.signed .i32 eighth, world) := by
    have evaluated := evaluate_embedded_directIndex leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
      (((((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth)).push (.signed .i32 sixth)).push (.signed .i32 seventh)) 0 1 7 (by simp)
      (by simp [base, lengthEnvironment, Model.keywordEnvironment])
      (by simp [base, lengthEnvironment, Model.keywordEnvironment]) bound7
    have valueEq : [first, second, third, fourth, fifth, sixth, seventh, eighth].get ⟨7, by simp⟩ = eighth := by rfl
    rw [valueEq] at evaluated
    simpa [world, base] using evaluated
  unfold KeywordCommand.directLoad8
  apply run_letValue_preserving world base KeywordCommand.i32 _ _
    (.signed .i32 first) completion index0
  apply run_letValue_preserving world (base.push (.signed .i32 first)) KeywordCommand.i32 _ _
    (.signed .i32 second) completion index1
  apply run_letValue_preserving world ((base.push (.signed .i32 first)).push (.signed .i32 second)) KeywordCommand.i32 _ _
    (.signed .i32 third) completion index2
  apply run_letValue_preserving world (((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)) KeywordCommand.i32 _ _
    (.signed .i32 fourth) completion index3
  apply run_letValue_preserving world ((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)) KeywordCommand.i32 _ _
    (.signed .i32 fifth) completion index4
  apply run_letValue_preserving world (((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth)) KeywordCommand.i32 _ _
    (.signed .i32 sixth) completion index5
  apply run_letValue_preserving world ((((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth)).push (.signed .i32 sixth)) KeywordCommand.i32 _ _
    (.signed .i32 seventh) completion index6
  apply run_letValue_preserving world (((((((base.push (.signed .i32 first)).push (.signed .i32 second)).push (.signed .i32 third)).push (.signed .i32 fourth)).push (.signed .i32 fifth)).push (.signed .i32 sixth)).push (.signed .i32 seventh)) KeywordCommand.i32 _ _
    (.signed .i32 eighth) completion index7
  simpa [world, base, loaded8Environment, loaded7Environment, loaded6Environment,
    loaded5Environment, loaded4Environment, loaded3Environment, loaded2Environment,
    loaded1Environment] using bodyResult

theorem length8Rules_loaded
    (leading trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int) :
    ∀ bytes constant, (bytes, constant) ∈ KeywordCommand.length8Rules →
      ∀ position expected, (position, expected) ∈ bytes →
        ∃ actual, loaded8Environment leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth
          position = .signed .i32 actual := by
  intro bytes constant member position expected byteMember
  simp [KeywordCommand.length8Rules] at member
  rcases member with ⟨rfl, rfl⟩
  simp at byteMember
  rcases byteMember with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    first
    | exact ⟨first, loaded8Environment_four leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth⟩
    | exact ⟨second, loaded8Environment_five leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth⟩
    | exact ⟨third, loaded8Environment_six leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth⟩
    | exact ⟨fourth, loaded8Environment_seven leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth⟩
    | exact ⟨fifth, loaded8Environment_eight leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth⟩
    | exact ⟨sixth, loaded8Environment_nine leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth⟩
    | exact ⟨seventh, loaded8Environment_ten leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth⟩
    | exact ⟨eighth, loaded8Environment_eleven leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth⟩

theorem directLoad8_noMatch_evaluates
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int)
    (spellingShape : spelling = [first, second, third, fourth, fifth, sixth, seventh, eighth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (noMatch : KeywordLengthSemantics.firstMatchingConstant
      (loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth) KeywordCommand.length8Rules = none) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing)) (lengthEnvironment leading spelling trailing)
      (KeywordCommand.directLoad8 (KeywordCommand.directChoices KeywordCommand.length8Rules)) =
      some (.next, Model.keywordWorld (leading ++ spelling ++ trailing), lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad8_evaluates_of_body leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth _ .next rfl bounded
  exact KeywordLengthSemantics.directChoices_noMatch_evaluates
    (environment := loaded8Environment leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth)
    (rules := KeywordCommand.length8Rules) (length8Rules_loaded leading trailing first second third fourth fifth sixth seventh eighth) noMatch

theorem directLoad8_match_evaluates
    (leading spelling trailing : List Int) (first second third fourth fifth sixth seventh eighth : Int) (constant : ConstantId) (declaration : Constant)
    (spellingShape : spelling = [first, second, third, fourth, fifth, sixth, seventh, eighth])
    (bounded : (leading ++ spelling ++ trailing).length ≤ 2147483647)
    (selected : KeywordLengthSemantics.firstMatchingConstant
      (loaded8Environment leading spelling trailing first second third fourth fifth sixth seventh eighth) KeywordCommand.length8Rules = some constant)
    (found : verifiedFrontendCore.constant? constant = some declaration) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing)) (lengthEnvironment leading spelling trailing)
      (KeywordCommand.directLoad8 (KeywordCommand.directChoices KeywordCommand.length8Rules)) =
      some (.returned (some declaration.value), Model.keywordWorld (leading ++ spelling ++ trailing),
        lengthEnvironment leading spelling trailing) := by
  subst spelling
  apply directLoad8_evaluates_of_body leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth _
    (.returned (some declaration.value)) rfl bounded
  exact KeywordLengthSemantics.directChoices_match_evaluates
    (environment := loaded8Environment leading [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing first second third fourth fifth sixth seventh eighth)
    (rules := KeywordCommand.length8Rules) (length8Rules_loaded leading trailing first second third fourth fifth sixth seventh eighth)
    selected declaration found

def decisionValue (environment : Env arity)
    (rules : List (List (Fin arity × Int) × ConstantId)) : Option Value :=
  let id := (KeywordLengthSemantics.firstMatchingConstant environment rules).getD 7
  (verifiedFrontendCore.constant? id).map (fun declaration => declaration.value)

theorem length2_firstMatching_formula
    (leading trailing : List Int) (first second : Int) :
    KeywordLengthSemantics.firstMatchingConstant
      (loaded2Environment leading [first, second] trailing first second)
      KeywordCommand.length2Rules =
    if (first == 102) && (second == 110) then some 61
    else if (first == 105) && (second == 102) then some 64
    else if (first == 105) && (second == 110) then some 81
    else none := by
  simp only [KeywordLengthSemantics.firstMatchingConstant,
    KeywordLengthSemantics.ruleMatches, KeywordCommand.length2Rules,
    Bool.and_eq_true]
  rw [loaded2Environment_at_four leading [first, second] trailing first second
    _ (by rfl)]
  rw [loaded2Environment_at_five leading [first, second] trailing first second
    _ (by rfl)]
  simp only [beq_iff_eq]
  simp only [and_true]

private theorem constant61 : verifiedFrontendCore.constant? 61 = some {
    id := 61, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.fnKeyword.gpuCode) } := by rfl

private theorem constant61_value : ∃ declaration,
    verifiedFrontendCore.constant? 61 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.fnKeyword.gpuCode) :=
  ⟨_, constant61, rfl⟩

private theorem constant64 : verifiedFrontendCore.constant? 64 = some {
    id := 64, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.ifKeyword.gpuCode) } := by rfl

private theorem constant64_value : ∃ declaration,
    verifiedFrontendCore.constant? 64 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.ifKeyword.gpuCode) := by
  exact ⟨_, constant64, rfl⟩

private theorem constant81 : verifiedFrontendCore.constant? 81 = some {
    id := 81, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.inKeyword.gpuCode) } := by rfl

private theorem constant81_value : ∃ declaration,
    verifiedFrontendCore.constant? 81 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.inKeyword.gpuCode) := by
  exact ⟨_, constant81, rfl⟩

private theorem constant7 : verifiedFrontendCore.constant? 7 = some {
    id := 7, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.identifier.gpuCode) } := by rfl

private theorem constant7_value : ∃ declaration,
    verifiedFrontendCore.constant? 7 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.identifier.gpuCode) := by
  exact ⟨_, constant7, rfl⟩

theorem length3_firstMatching_formula
    (leading trailing : List Int) (first second third : Int) :
    KeywordLengthSemantics.firstMatchingConstant
      (loaded3Environment leading [first, second, third] trailing first second third)
      KeywordCommand.length3Rules =
    if first = 112 ∧ second = 117 ∧ third = 98 then some 60
    else if first = 108 ∧ second = 101 ∧ third = 116 then some 62
    else if first = 102 ∧ second = 111 ∧ third = 114 then some 80
    else none := by
  simp only [KeywordLengthSemantics.firstMatchingConstant,
    KeywordLengthSemantics.ruleMatches, KeywordCommand.length3Rules,
    Bool.and_eq_true]
  rw [loaded3Environment_at_four leading [first, second, third] trailing first second third _ (by rfl)]
  rw [loaded3Environment_at_five leading [first, second, third] trailing first second third _ (by rfl)]
  rw [loaded3Environment_at_six leading [first, second, third] trailing first second third _ (by rfl)]
  simp only [beq_iff_eq, and_true]

private theorem constant60 : verifiedFrontendCore.constant? 60 = some {
    id := 60, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.pubKeyword.gpuCode) } := by rfl

private theorem constant60_value : ∃ declaration,
    verifiedFrontendCore.constant? 60 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.pubKeyword.gpuCode) :=
  ⟨_, constant60, rfl⟩

private theorem constant62 : verifiedFrontendCore.constant? 62 = some {
    id := 62, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.letKeyword.gpuCode) } := by rfl

private theorem constant62_value : ∃ declaration,
    verifiedFrontendCore.constant? 62 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.letKeyword.gpuCode) :=
  ⟨_, constant62, rfl⟩

private theorem constant80 : verifiedFrontendCore.constant? 80 = some {
    id := 80, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.forKeyword.gpuCode) } := by rfl

private theorem constant80_value : ∃ declaration,
    verifiedFrontendCore.constant? 80 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.forKeyword.gpuCode) :=
  ⟨_, constant80, rfl⟩

theorem length3_decisionValue
    (leading trailing : List Int) (first second third : Int) :
    decisionValue (loaded3Environment leading [first, second, third] trailing first second third)
      KeywordCommand.length3Rules =
    some (.signed .i32 (Model.keywordKind [first, second, third] 0 3)) := by
  rw [show decisionValue (loaded3Environment leading [first, second, third] trailing first second third)
      KeywordCommand.length3Rules =
      (verifiedFrontendCore.constant?
        ((KeywordLengthSemantics.firstMatchingConstant
          (loaded3Environment leading [first, second, third] trailing first second third)
          KeywordCommand.length3Rules).getD 7)).map
            (fun declaration => declaration.value) by rfl]
  rw [length3_firstMatching_formula]
  simp [Model.keywordKind, Model.keywordSpan,
    Lanius.Compiler.Lexer.exactKeywordKind, Lanius.Compiler.Lexer.keywordRules]
  by_cases rule0 : first = 112 ∧ second = 117 ∧ third = 98
  · simpa [rule0] using constant60_value
  by_cases rule1 : first = 108 ∧ second = 101 ∧ third = 116
  · simpa [rule1] using constant62_value
  by_cases rule2 : first = 102 ∧ second = 111 ∧ third = 114
  · simpa [rule2] using constant80_value
  have rule0Nat : ¬(first.toNat = 112 ∧ second.toNat = 117 ∧ third.toNat = 98) := by omega
  have rule1Nat : ¬(first.toNat = 108 ∧ second.toNat = 101 ∧ third.toNat = 116) := by omega
  have rule2Nat : ¬(first.toNat = 102 ∧ second.toNat = 111 ∧ third.toNat = 114) := by omega
  simpa [rule0, rule1, rule2, rule0Nat, rule1Nat, rule2Nat] using constant7_value


theorem length4_firstMatching_formula
    (leading trailing : List Int) (first second third fourth : Int) :
    KeywordLengthSemantics.firstMatchingConstant
      (loaded4Environment leading [first, second, third, fourth] trailing first second third fourth)
      KeywordCommand.length4Rules =
    if first = 101 ∧ second = 108 ∧ third = 115 ∧ fourth = 101 then some 65
    else if first = 116 ∧ second = 114 ∧ third = 117 ∧ fourth = 101 then some 70
    else if first = 101 ∧ second = 110 ∧ third = 117 ∧ fourth = 109 then some 73
    else if first = 105 ∧ second = 109 ∧ third = 112 ∧ fourth = 108 then some 78
    else if first = 115 ∧ second = 101 ∧ third = 108 ∧ fourth = 102 then some 85
    else if first = 116 ∧ second = 121 ∧ third = 112 ∧ fourth = 101 then some 83
    else none := by
  simp only [KeywordLengthSemantics.firstMatchingConstant,
    KeywordLengthSemantics.ruleMatches, KeywordCommand.length4Rules,
    Bool.and_eq_true]
  rw [loaded4Environment_at_four leading [first, second, third, fourth] trailing first second third fourth _ (by rfl)]
  rw [loaded4Environment_at_five leading [first, second, third, fourth] trailing first second third fourth _ (by rfl)]
  rw [loaded4Environment_at_six leading [first, second, third, fourth] trailing first second third fourth _ (by rfl)]
  rw [loaded4Environment_at_seven leading [first, second, third, fourth] trailing first second third fourth _ (by rfl)]
  simp only [beq_iff_eq, and_true]

private theorem constant65 : verifiedFrontendCore.constant? 65 = some {
    id := 65, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.elseKeyword.gpuCode) } := by rfl

private theorem constant65_value : ∃ declaration,
    verifiedFrontendCore.constant? 65 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.elseKeyword.gpuCode) :=
  ⟨_, constant65, rfl⟩

private theorem constant70 : verifiedFrontendCore.constant? 70 = some {
    id := 70, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.trueKeyword.gpuCode) } := by rfl

private theorem constant70_value : ∃ declaration,
    verifiedFrontendCore.constant? 70 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.trueKeyword.gpuCode) :=
  ⟨_, constant70, rfl⟩

private theorem constant73 : verifiedFrontendCore.constant? 73 = some {
    id := 73, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.enumKeyword.gpuCode) } := by rfl

private theorem constant73_value : ∃ declaration,
    verifiedFrontendCore.constant? 73 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.enumKeyword.gpuCode) :=
  ⟨_, constant73, rfl⟩

private theorem constant78 : verifiedFrontendCore.constant? 78 = some {
    id := 78, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.implKeyword.gpuCode) } := by rfl

private theorem constant78_value : ∃ declaration,
    verifiedFrontendCore.constant? 78 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.implKeyword.gpuCode) :=
  ⟨_, constant78, rfl⟩

private theorem constant85 : verifiedFrontendCore.constant? 85 = some {
    id := 85, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.selfKeyword.gpuCode) } := by rfl

private theorem constant85_value : ∃ declaration,
    verifiedFrontendCore.constant? 85 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.selfKeyword.gpuCode) :=
  ⟨_, constant85, rfl⟩

private theorem constant83 : verifiedFrontendCore.constant? 83 = some {
    id := 83, type := KeywordCommand.i32,
    value := .signed .i32 (Int.ofNat TokenKind.typeKeyword.gpuCode) } := by rfl

private theorem constant83_value : ∃ declaration,
    verifiedFrontendCore.constant? 83 = some declaration ∧
      declaration.value = .signed .i32 (Int.ofNat TokenKind.typeKeyword.gpuCode) :=
  ⟨_, constant83, rfl⟩

theorem length4_decisionValue
    (leading trailing : List Int) (first second third fourth : Int) :
    decisionValue (loaded4Environment leading [first, second, third, fourth] trailing first second third fourth)
      KeywordCommand.length4Rules =
    some (.signed .i32 (Model.keywordKind [first, second, third, fourth] 0 4)) := by
  rw [show decisionValue (loaded4Environment leading [first, second, third, fourth] trailing first second third fourth)
      KeywordCommand.length4Rules =
      (verifiedFrontendCore.constant?
        ((KeywordLengthSemantics.firstMatchingConstant
          (loaded4Environment leading [first, second, third, fourth] trailing first second third fourth)
          KeywordCommand.length4Rules).getD 7)).map
            (fun declaration => declaration.value) by rfl]
  rw [length4_firstMatching_formula]
  simp [Model.keywordKind, Model.keywordSpan,
    Lanius.Compiler.Lexer.exactKeywordKind, Lanius.Compiler.Lexer.keywordRules]
  by_cases rule0 : first = 101 ∧ second = 108 ∧ third = 115 ∧ fourth = 101
  · simpa [rule0] using constant65_value
  by_cases rule1 : first = 116 ∧ second = 114 ∧ third = 117 ∧ fourth = 101
  · simpa [rule1] using constant70_value
  by_cases rule2 : first = 101 ∧ second = 110 ∧ third = 117 ∧ fourth = 109
  · simpa [rule2] using constant73_value
  by_cases rule3 : first = 105 ∧ second = 109 ∧ third = 112 ∧ fourth = 108
  · simpa [rule3] using constant78_value
  by_cases rule4 : first = 115 ∧ second = 101 ∧ third = 108 ∧ fourth = 102
  · simpa [rule4] using constant85_value
  by_cases rule5 : first = 116 ∧ second = 121 ∧ third = 112 ∧ fourth = 101
  · simpa [rule5] using constant83_value
  have rule0Nat : ¬(first.toNat = 101 ∧ second.toNat = 108 ∧ third.toNat = 115 ∧ fourth.toNat = 101) := by omega
  have rule1Nat : ¬(first.toNat = 116 ∧ second.toNat = 114 ∧ third.toNat = 117 ∧ fourth.toNat = 101) := by omega
  have rule2Nat : ¬(first.toNat = 101 ∧ second.toNat = 110 ∧ third.toNat = 117 ∧ fourth.toNat = 109) := by omega
  have rule3Nat : ¬(first.toNat = 105 ∧ second.toNat = 109 ∧ third.toNat = 112 ∧ fourth.toNat = 108) := by omega
  have rule4Nat : ¬(first.toNat = 115 ∧ second.toNat = 101 ∧ third.toNat = 108 ∧ fourth.toNat = 102) := by omega
  have rule5Nat : ¬(first.toNat = 116 ∧ second.toNat = 121 ∧ third.toNat = 112 ∧ fourth.toNat = 101) := by omega
  simpa [rule0, rule1, rule2, rule3, rule4, rule5, rule0Nat, rule1Nat, rule2Nat, rule3Nat, rule4Nat, rule5Nat] using constant7_value


theorem length2_decisionValue
    (leading trailing : List Int) (first second : Int) :
    decisionValue
      (loaded2Environment leading [first, second] trailing first second)
      KeywordCommand.length2Rules =
    some (.signed .i32 (Model.keywordKind [first, second] 0 2)) := by
  rw [show decisionValue
      (loaded2Environment leading [first, second] trailing first second)
      KeywordCommand.length2Rules =
      (verifiedFrontendCore.constant?
        ((KeywordLengthSemantics.firstMatchingConstant
          (loaded2Environment leading [first, second] trailing first second)
          KeywordCommand.length2Rules).getD 7)).map
            (fun declaration => declaration.value) by rfl]
  rw [length2_firstMatching_formula]
  simp [Model.keywordKind,
    Model.keywordSpan, Lanius.Compiler.Lexer.exactKeywordKind,
    Lanius.Compiler.Lexer.keywordRules]
  by_cases fnKeyword : first = 102 ∧ second = 110
  · simpa [fnKeyword] using constant61_value
  by_cases ifKeyword : first = 105 ∧ second = 102
  · simpa [fnKeyword, ifKeyword] using constant64_value
  by_cases inKeyword : first = 105 ∧ second = 110
  · simpa [fnKeyword, ifKeyword, inKeyword] using constant81_value
  have fnKeywordNat : ¬(first.toNat = 102 ∧ second.toNat = 110) := by
    omega
  have ifKeywordNat : ¬(first.toNat = 105 ∧ second.toNat = 102) := by
    omega
  have inKeywordNat : ¬(first.toNat = 105 ∧ second.toNat = 110) := by
    omega
  simpa [fnKeyword, ifKeyword, inKeyword, fnKeywordNat, ifKeywordNat,
    inKeywordNat] using constant7_value


attribute [local simp]
  KeywordCommand.command KeywordCommand.directCommand
  KeywordCommand.directLengthBranch
  KeywordCommand.directLoad2 KeywordCommand.directLoad3
  KeywordCommand.directLoad4 KeywordCommand.directLoad5
  KeywordCommand.directLoad6 KeywordCommand.directLoad8
  KeywordCommand.directChoices KeywordCommand.directAllEqual
  KeywordCommand.directReturned KeywordCommand.directIndex
  KeywordCommand.directEqual KeywordCommand.directAdd
  KeywordCommand.directBinary KeywordCommand.directConstant
  KeywordCommand.directLiteral KeywordCommand.directSlot
  KeywordCommand.length2Rules KeywordCommand.length3Rules
  KeywordCommand.length4Rules KeywordCommand.length5Rules
  KeywordCommand.length6Rules KeywordCommand.length8Rules
  Lanius.FunctionalView.Stateful.Acyclic.run?
  Lanius.FunctionalView.Core.Stateful.termMachine
  Lanius.FunctionalView.Term.evaluate Lanius.FunctionalView.evaluateTerms
  Lanius.FunctionalView.Ref.evaluate
  Lanius.FunctionalView.Env.push
  Lanius.FunctionalView.Core.Effectful.evaluateOperation
  Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
  Lanius.FunctionalView.Core.ReadOnly.readI32Slice
  Lanius.Semantics.evalBinaryValue Lanius.Semantics.evalSignedBinary
  Lanius.Semantics.scalarEqual
  Model.noCalls Model.keywordEnvironment Model.keywordSource
  Model.keywordWorld Lanius.FunctionalView.Core.ReadOnly.World.singleton

end Lanius.Extraction.CanonicalTokens.KeywordSemantics
