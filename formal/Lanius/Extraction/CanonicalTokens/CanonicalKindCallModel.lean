import Lanius.Extraction.CanonicalTokens.CanonicalKind
import Lanius.FunctionalViewCoreFreshSimulation

namespace Lanius.Extraction.CanonicalTokens.CanonicalKindCallModel

open Lanius
open Lanius.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.Extraction.CanonicalTokens.Functions

def i32 : Ty := .scalar (.signed .i32)

/-- The public call boundary for `canonical_kind`.  Nested `keyword_kind`
calls are deliberately not folded into this model; callers compose this leaf
with the independently proved canonical-token helper registry. -/
def calls : CallModel where
  evaluate := fun world function arguments =>
    if function = canonicalKindFunction.id then
      match arguments with
      | [.slice (.scalar (.signed .i32)) cell [] 0 length,
          .signed .i32 rawKind, .signed .i32 start, .signed .i32 finish] =>
          if 0 ≤ start ∧ start ≤ finish ∧ finish ≤ 2147483647 ∧
              length ≤ 2147483647 then
            match world.i32Slice? cell with
            | some source =>
                if length = source.length ∧ source.length ≤ 2147483647 ∧
                    finish.toNat ≤ source.length then
                  .ok (.signed .i32
                    (CanonicalKind.result source rawKind start.toNat
                      finish.toNat), world)
                else .error .arrayBounds
            | none => .error .invalidPointer
          else .error .arrayBounds
      | _ => .error .typeMismatch
    else .error .invalidPointer

theorem evaluate (world : Lanius.FunctionalView.Core.ReadOnly.World)
    (source : List Int)
    (cell : CellId) (rawKind : Int) (start finish : Nat)
    (sourceFound : world.i32Slice? cell = some source)
    (ordered : start ≤ finish) (inBounds : finish ≤ source.length)
    (sourceFitsI32 : source.length ≤ 2147483647) :
    calls.evaluate world canonicalKindFunction.id
        [.slice i32 cell [] 0 source.length, .signed .i32 rawKind,
          .signed .i32 start, .signed .i32 finish] =
      .ok (.signed .i32 (CanonicalKind.result source rawKind start finish),
        world) := by
  have startNonnegative : (0 : Int) ≤ (start : Int) := by omega
  have startLeFinish : (start : Int) ≤ (finish : Int) := by omega
  have finishFitsI32 : (finish : Int) ≤ 2147483647 := by omega
  simp [calls, i32, sourceFound, startNonnegative, startLeFinish,
    finishFitsI32, inBounds, sourceFitsI32]

theorem success
    (evaluated : calls.evaluate world function arguments =
      .ok (result, afterWorld)) :
    ∃ (source : List Int) (cell : CellId) (rawKind : Int)
      (start finish : Nat),
      world.i32Slice? cell = some source ∧
      function = canonicalKindFunction.id ∧
      arguments = [.slice i32 cell [] 0 source.length,
        .signed .i32 rawKind, .signed .i32 start, .signed .i32 finish] ∧
      start ≤ finish ∧ finish ≤ source.length ∧
      source.length ≤ 2147483647 ∧
      result = .signed .i32
        (CanonicalKind.result source rawKind start finish) ∧
      afterWorld = world := by
  simp only [calls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next cell length rawKind startInt finishInt =>
      split at evaluated
      next valid =>
        split at evaluated
        next sourceList sourceFound =>
          split at evaluated
          next sourceValid =>
            obtain ⟨rfl, rfl⟩ := evaluated
            let start := startInt.toNat
            let finish := finishInt.toNat
            have startEq : (start : Int) = startInt := by
              simp [start]
              omega
            have finishEq : (finish : Int) = finishInt := by
              simp [finish]
              omega
            refine ⟨sourceList, cell, rawKind, start, finish,
              sourceFound, functionEq, ?_, ?_, ?_, sourceValid.2.1, ?_, rfl⟩
            · simp [i32, sourceValid.1, startEq, finishEq]
            · omega
            · exact sourceValid.2.2
            · rfl
          next => contradiction
        next => contradiction
      next => contradiction
    next => contradiction
  next => contradiction

theorem worldPreserving :
    Lanius.FunctionalView.FreshSimulation.WorldPreserving calls := by
  intro beforeWorld afterWorld function values value evaluated
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, afterEq⟩ := success evaluated
  exact afterEq

end Lanius.Extraction.CanonicalTokens.CanonicalKindCallModel
