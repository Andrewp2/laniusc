import Lanius.Compiler.LexerCanonical
import Lanius.Extraction.CanonicalTokens.Functions
import Lanius.Extraction.CanonicalTokens.Model
import Lanius.FunctionalViewStatefulAcyclic
import Lanius.FunctionalViewStatefulPattern
import Lanius.FunctionalViewCoreEffectful

namespace Lanius.Extraction.CanonicalTokens.CanonicalKind

set_option maxRecDepth 100000

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful.Pattern
open Lanius.Extraction.CanonicalTokens.Functions

def keywordKind (source : List Int) (start finish : Nat) : Int :=
  Model.keywordKind source start finish

def result (source : List Int) (rawKind : Int) (start finish : Nat) : Int :=
  if rawKind = Int.ofNat TokenKind.identifier.gpuCode then
    keywordKind source start finish
  else
    rawKind

def world (source : List Int) : World := World.singleton 0 source

def sourceValue (source : List Int) : Value :=
  .slice (.scalar (.signed .i32)) 0 [] 0 source.length

def environment (source : List Int) (rawKind : Int) (start finish : Nat) : Env 4
  | ⟨0, _⟩ => sourceValue source
  | ⟨1, _⟩ => .signed .i32 rawKind
  | ⟨2, _⟩ => .signed .i32 start
  | ⟨3, _⟩ => .signed .i32 finish

def calls : Lanius.FunctionalView.Core.Effectful.CallModel := Model.callModel

private def i32 : Ty := .scalar (.signed .i32)

private theorem identifierConstant :
    verifiedFrontendCore.constant? 7 = some {
      id := 7
      type := i32
      value := .signed .i32 (Int.ofNat TokenKind.identifier.gpuCode)
    } := by
  rfl

private def exactOperation (operation : Operation) : Exact Operation :=
  Exact.ofDecidableEq operation

private def pattern : CommandPattern Core.signature actions 4 :=
  .sequence
    (.ifThenElse
      (.apply (exactOperation (.binary .equal i32 i32 (.scalar .bool)))
        [.slot ⟨1, by omega⟩,
          .apply (exactOperation (.constant 7 i32)) []])
      (.sequence
        (.returnValue (some
          (.apply (exactOperation
              (.call keywordKindFunction.id [
                .slice i32, i32, i32] i32))
            [.slot ⟨0, by omega⟩, .slot ⟨2, by omega⟩,
              .slot ⟨3, by omega⟩])))
        .skip)
      .skip)
    (.sequence (.returnValue (some (.slot ⟨1, by omega⟩))) .skip)

private def command : Lanius.FunctionalView.Stateful.Command
    Core.signature actions 4 :=
  .sequence
    (.ifThenElse
      (.apply (.binary .equal i32 i32 (.scalar .bool))
        [.reference (.slot ⟨1, by omega⟩),
          .apply (.constant 7 i32) []])
      (.sequence
        (.returnValue (some
          (.apply (.call keywordKindFunction.id [.slice i32, i32, i32] i32)
            [.reference (.slot ⟨0, by omega⟩),
              .reference (.slot ⟨2, by omega⟩),
              .reference (.slot ⟨3, by omega⟩)])))
        .skip)
      .skip)
    (.sequence (.returnValue (some (.reference (.slot ⟨1, by omega⟩)))) .skip)

theorem reified :
    reification4? canonicalKindFunction canonicalKindBody =
      some canonicalKindView := by
  simp [canonicalKindView]

theorem canonicalKindView_command : canonicalKindView.command = command := by
  calc
    canonicalKindView.command = pattern.denote := exact_of_matches (by native_decide)
    _ = command := (exact_of_matches
      (candidate := command) (by native_decide)).symm

private def run (source : List Int) (rawKind : Int) (start finish : Nat) :=
  Lanius.FunctionalView.Stateful.Acyclic.run?
    (Lanius.FunctionalView.Core.Effectful.machine verifiedFrontendCore
      calls)
    (machineWith verifiedFrontendCore
      (fun world =>
        Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore calls world))
    (world source) (environment source rawKind start finish) command

/-- The exact checked `canonical_kind` view either retains the raw kind or
delegates identifier spelling to the proved keyword classifier. -/
theorem view_evaluates (source : List Int) (rawKind : Int)
    (start finish : Nat) (ordered : start ≤ finish)
    (inBounds : finish ≤ source.length)
    (sourceFitsI32 : source.length ≤ 2147483647) :
    ∃ afterEnvironment,
      run source rawKind start finish = some (
        .returned (some (.signed .i32 (result source rawKind start finish))),
        world source, afterEnvironment) := by
  by_cases identifier : rawKind = Int.ofNat TokenKind.identifier.gpuCode
  · subst rawKind
    have keywordCall :=
      Model.callModel_keywordKind source start finish ordered inBounds sourceFitsI32
    have keywordCall' :
        Model.callModel.evaluate (world source) keywordKindFunction.id
            [sourceValue source, .signed .i32 start, .signed .i32 finish] =
          .ok (.signed .i32 (keywordKind source start finish), world source) := by
      simpa [Model.keywordWorld, Model.keywordSource, keywordKind, world,
        sourceValue] using keywordCall
    simp only [world, sourceValue] at keywordCall'
    simp [run, result, world, sourceValue, environment, command, pattern,
      exactOperation, i32, reified, calls,
      CommandPattern.denote, TermPattern.denote,
      Lanius.FunctionalView.Stateful.Acyclic.run?, Term.evaluate,
      evaluateTerms, Ref.evaluate, Lanius.FunctionalView.Core.Effectful.machine,
      Lanius.FunctionalView.Core.Effectful.evaluateOperation,
      Lanius.FunctionalView.Core.ReadOnly.evaluateOperation, bind, Except.bind,
      Lanius.Semantics.evalBinaryValue, Lanius.Semantics.scalarEqual,
      identifierConstant]
    rw [keywordCall']
    simp
  · have identifierCast :
        rawKind ≠ (TokenKind.identifier.gpuCode : Int) := by
      simpa only [Int.ofNat_eq_natCast] using identifier
    have notIdentifier :
        (rawKind == (TokenKind.identifier.gpuCode : Int)) = false :=
      beq_eq_false_iff_ne.mpr identifierCast
    simp [run, result, world, sourceValue, environment, command, pattern,
      exactOperation, i32, reified, calls,
      CommandPattern.denote, TermPattern.denote,
      Lanius.FunctionalView.Stateful.Acyclic.run?, Term.evaluate,
      evaluateTerms, Ref.evaluate, Lanius.FunctionalView.Core.Effectful.machine,
      Lanius.FunctionalView.Core.Effectful.evaluateOperation,
      Lanius.FunctionalView.Core.ReadOnly.evaluateOperation, bind, Except.bind,
      Lanius.Semantics.evalBinaryValue, Lanius.Semantics.scalarEqual,
      identifierConstant, identifier, identifierCast, notIdentifier]

/-- Relational form of `view_evaluates`, suitable for the verified
FunctionalView-to-Core simulation.  The world equation states that
`canonical_kind` is read-only. -/
theorem view_executes (source : List Int) (rawKind : Int)
    (start finish : Nat) (ordered : start ≤ finish)
    (inBounds : finish ≤ source.length)
    (sourceFitsI32 : source.length ≤ 2147483647) :
    ∃ afterEnvironment,
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (Lanius.FunctionalView.Core.Effectful.machine verifiedFrontendCore
          calls)
        (machineWith verifiedFrontendCore
          (fun world =>
            Lanius.FunctionalView.Core.Effectful.evaluateOperation
              verifiedFrontendCore calls world))
        (world source) (environment source rawKind start finish)
        canonicalKindView.command
        (.returned (some (.signed .i32
          (result source rawKind start finish))))
        (world source) afterEnvironment := by
  obtain ⟨afterEnvironment, ran⟩ :=
    view_evaluates source rawKind start finish ordered inBounds sourceFitsI32
  refine ⟨afterEnvironment, ?_⟩
  rw [canonicalKindView_command]
  exact Lanius.FunctionalView.Stateful.Acyclic.run?_sound ran

def sourceValueAt (cell : CellId) (source : List Int) : Value :=
  .slice (.scalar (.signed .i32)) cell [] 0 source.length

def environmentInWorld (cell : CellId) (source : List Int)
    (rawKind : Int) (start finish : Nat) : Env 4
  | ⟨0, _⟩ => sourceValueAt cell source
  | ⟨1, _⟩ => .signed .i32 rawKind
  | ⟨2, _⟩ => .signed .i32 start
  | ⟨3, _⟩ => .signed .i32 finish

private def runInWorld (beforeWorld : World) (cell : CellId)
    (source : List Int) (rawKind : Int) (start finish : Nat) :=
  Lanius.FunctionalView.Stateful.Acyclic.run?
    (Lanius.FunctionalView.Core.Effectful.machine verifiedFrontendCore calls)
    (machineWith verifiedFrontendCore
      (fun world =>
        Lanius.FunctionalView.Core.Effectful.evaluateOperation
          verifiedFrontendCore calls world))
    beforeWorld (environmentInWorld cell source rawKind start finish) command

private theorem callModel_keywordKind_in_world
    (beforeWorld : World) (cell : CellId) (source : List Int)
    (start finish : Nat) (sourceFound : beforeWorld.i32Slice? cell = some source)
    (ordered : start ≤ finish) (inBounds : finish ≤ source.length)
    (sourceFitsI32 : source.length ≤ 2147483647) :
    Model.callModel.evaluate beforeWorld keywordKindFunction.id
        [sourceValueAt cell source, .signed .i32 start, .signed .i32 finish] =
      .ok (.signed .i32 (keywordKind source start finish), beforeWorld) := by
  have distinct : keywordKindFunction.id ≠ isTriviaFunction.id := by
    native_decide
  simp [Model.callModel, sourceValueAt, distinct, sourceFound, ordered,
    inBounds, sourceFitsI32, keywordKind]

/-- The checked `canonical_kind` view is valid for a source slice embedded in
an arbitrary represented world, not only for the isolated cell-zero test
world.  This is the form required by callers such as the in-place compactor. -/
theorem view_executes_in_world
    (beforeWorld : World) (cell : CellId) (source : List Int)
    (rawKind : Int) (start finish : Nat)
    (sourceFound : beforeWorld.i32Slice? cell = some source)
    (ordered : start ≤ finish) (inBounds : finish ≤ source.length)
    (sourceFitsI32 : source.length ≤ 2147483647) :
    ∃ afterEnvironment,
      Lanius.FunctionalView.Stateful.Command.Evaluates
        (Lanius.FunctionalView.Core.Effectful.machine verifiedFrontendCore
          calls)
        (machineWith verifiedFrontendCore
          (fun world =>
            Lanius.FunctionalView.Core.Effectful.evaluateOperation
              verifiedFrontendCore calls world))
        beforeWorld (environmentInWorld cell source rawKind start finish)
        canonicalKindView.command
        (.returned (some (.signed .i32
          (result source rawKind start finish))))
        beforeWorld afterEnvironment := by
  have ran : ∃ afterEnvironment,
      runInWorld beforeWorld cell source rawKind start finish = some (
        .returned (some (.signed .i32 (result source rawKind start finish))),
        beforeWorld, afterEnvironment) := by
    by_cases identifier :
        rawKind = Int.ofNat TokenKind.identifier.gpuCode
    · subst rawKind
      have keywordCall := callModel_keywordKind_in_world beforeWorld cell
        source start finish sourceFound ordered inBounds sourceFitsI32
      have keywordCall' :
          Model.callModel.evaluate beforeWorld keywordKindFunction.id
              [.slice (.scalar (.signed .i32)) cell [] 0 source.length,
                .signed .i32 start, .signed .i32 finish] =
            .ok (.signed .i32 (keywordKind source start finish),
              beforeWorld) := by
        simpa [sourceValueAt] using keywordCall
      simp [runInWorld, result, environmentInWorld, sourceValueAt, command,
        pattern, exactOperation, i32, reified, calls,
        CommandPattern.denote, TermPattern.denote,
        Lanius.FunctionalView.Stateful.Acyclic.run?, Term.evaluate,
        evaluateTerms, Ref.evaluate,
        Lanius.FunctionalView.Core.Effectful.machine,
        Lanius.FunctionalView.Core.Effectful.evaluateOperation,
        Lanius.FunctionalView.Core.ReadOnly.evaluateOperation, bind,
        Except.bind, Lanius.Semantics.evalBinaryValue,
        Lanius.Semantics.scalarEqual, identifierConstant]
      rw [keywordCall']
      simp
    · have identifierCast :
          rawKind ≠ (TokenKind.identifier.gpuCode : Int) := by
        simpa only [Int.ofNat_eq_natCast] using identifier
      have notIdentifier :
          (rawKind == (TokenKind.identifier.gpuCode : Int)) = false :=
        beq_eq_false_iff_ne.mpr identifierCast
      simp [runInWorld, result, environmentInWorld, sourceValueAt, command,
        pattern, exactOperation, i32, reified, calls,
        CommandPattern.denote, TermPattern.denote,
        Lanius.FunctionalView.Stateful.Acyclic.run?, Term.evaluate,
        evaluateTerms, Ref.evaluate,
        Lanius.FunctionalView.Core.Effectful.machine,
        Lanius.FunctionalView.Core.Effectful.evaluateOperation,
        Lanius.FunctionalView.Core.ReadOnly.evaluateOperation, bind,
        Except.bind, Lanius.Semantics.evalBinaryValue,
        Lanius.Semantics.scalarEqual, identifierConstant, identifier,
        identifierCast, notIdentifier]
  obtain ⟨afterEnvironment, ran⟩ := ran
  refine ⟨afterEnvironment, ?_⟩
  rw [canonicalKindView_command]
  exact Lanius.FunctionalView.Stateful.Acyclic.run?_sound ran

end Lanius.Extraction.CanonicalTokens.CanonicalKind
