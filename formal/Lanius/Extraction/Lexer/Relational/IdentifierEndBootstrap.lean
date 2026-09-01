import Lanius.Extraction.Lexer.Relational.SourceMemory
import Lanius.Extraction.Lexer.Relational.IdentifierEndContract
import Lanius.Extraction.Lexer.Calls

namespace Lanius.Extraction.Lexer.Relational.IdentifierEnd.Bootstrap

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Extraction.Lexer
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.Relational

/-! # Temporary scanner migration bridge

Nothing in this module is part of the permanent algorithm-facing contract.
It adapts the already-proved source-indexed `CallModel` while the inverse
WP-to-Core adequacy theorem is being implemented.
-/

theorem modelImplements (source : List Byte) :
    ModelImplements (contract source) (Calls.identifierCalls source) := by
  constructor
  intro start before beforeWorld pre represented
  change Nat at start
  change List Byte at before
  change before = source ∧ source.length ≤ 2147483647 ∧
    start < source.length at pre
  change beforeWorld.i32Slice? 0 = some (sourceIntegers before) at represented
  obtain ⟨beforeEq, sourceBound, startInBounds⟩ := pre
  have startBound : start ≤ 2147483647 := by omega
  have sourceRepresented :
      beforeWorld.i32Slice? 0 = some (SourceMemory.sourceIntegers source) := by
    simpa [sourceIntegers, SourceMemory.sourceIntegers, beforeEq] using represented
  refine ⟨scanIdentifierEnd source start, before, beforeWorld, ?_, represented,
    ?_, rfl⟩
  · change (Calls.identifierCalls source).evaluate beforeWorld
      Scanners.scanIdentifierEndFunction.id (scannerArguments source start) =
        .ok (.signed .i32 (Int.ofNat (scanIdentifierEnd source start)),
          beforeWorld)
    simpa [Calls.identifierCalls, scannerArguments, sourceSlice,
      SourceMemory.scannerArguments, SourceMemory.sourceSlice] using
      Calls.scannerCalls_at_world source
        Scanners.scanIdentifierEndFunction.id false
        (fun cursor =>
          .signed .i32 (Int.ofNat (scanIdentifierEnd source cursor)))
        beforeWorld start sourceBound startInBounds startBound (by simp)
        sourceRepresented
  · exact ⟨rfl, scanIdentifierEnd_spec source start,
      scanIdentifierEnd_after_start source start,
      scanIdentifierEnd_le_source_length source start startInBounds⟩

theorem returnsCorrectly (source : List Byte) :
    ReturnsCorrectly (contract source) :=
  ReturnsCorrectly.ofFramePreservingModel
    (modelImplements source)
    (Calls.identifierFramePreservingCallSoundness source)

end Lanius.Extraction.Lexer.Relational.IdentifierEnd.Bootstrap
