import Lanius.Compiler.Lexer
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreStatefulSimulation

namespace Lanius.Extraction.Lexer.Relational.SourceMemory

open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation

/-! # Logical source representation for relational lexer proofs

This module contains only the immutable source encoding shared by lexer
contracts.  Keeping it separate from `Lexer.Calls` prevents new relational
proofs from importing the retained executable scanner models and constructive
whole-scanner execution theorems.
-/

def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

def sourceWorld (source : List Byte) : World :=
  World.singleton 0 (sourceIntegers source)

@[simp] theorem sourceWorld_finds (source : List Byte) :
    (sourceWorld source).i32Slice? 0 = some (sourceIntegers source) := by
  exact World.singleton_finds

def sourceSlice (source : List Byte) : Value :=
  .slice (.scalar (.signed .i32)) 0 [] 0 source.length

def scannerArguments (source : List Byte) (start : Nat) : List Value :=
  [sourceSlice source, .signed .i32 (Int.ofNat source.length),
    .signed .i32 (Int.ofNat start)]

/-- Restrict an arbitrary represented caller world to the immutable source
region while preserving all proof-local cells. -/
theorem representationOnlySource
    (represented : Representation layout localCell world environment state)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    Representation layout localCell (sourceWorld source) environment state := {
  worldOwned := by
    intro cell values found
    have cellEq : cell = 0 := by
      by_cases same : cell = 0
      · exact same
      · simp [sourceWorld, World.singleton, same] at found
    subst cell
    have valuesEq : values = sourceIntegers source := by
      simpa [sourceWorld, World.singleton] using found.symm
    subst values
    exact represented.worldOwned 0 (sourceIntegers source) sourceFound
  localOwned := represented.localOwned
  localCellsInjective := represented.localCellsInjective
  worldLocalsDisjoint := by
    intro cell worldMember localMember
    obtain ⟨values, found⟩ := worldMember
    have cellEq : cell = 0 := by
      by_cases same : cell = 0
      · exact same
      · simp [sourceWorld, World.singleton, same] at found
    subst cell
    exact represented.worldLocalsDisjoint 0
      ⟨sourceIntegers source, sourceFound⟩ localMember }

end Lanius.Extraction.Lexer.Relational.SourceMemory
