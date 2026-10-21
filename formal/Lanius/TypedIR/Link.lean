import Lanius.TypedIR.Statement

namespace Lanius.TypedIR.Intrinsic

open Lanius Core Typing

def assemble (signature : Signature) (functions : List (Function signature)) : Core.Program :=
  { signature.declarations with functions := functions.map Function.erase }

theorem assemble_realizes (signature : Signature) (functions : List (Function signature))
    (headers : functions.map (FunctionType.ofCore ∘ Function.erase) = signature.functions) :
    signature.Realizes (assemble signature functions) :=
  ⟨rfl, rfl, rfl, rfl, by simpa only [assemble, List.map_map] using headers⟩

/-- This theorem is shared by every extracted program. It traverses typed
    syntax in its proof, not in each emitted module's elaboration. -/
theorem assemble_wellTyped (signature : Signature) (functions : List (Function signature))
    (headers : functions.map (FunctionType.ofCore ∘ Function.erase) = signature.functions)
    (constants : ∀ constant ∈ signature.constants,
      ConstantWellTyped signature.declarations constant) :
    ProgramWellTyped (assemble signature functions) := by
  have linked := assemble_realizes signature functions headers
  constructor
  · intro constant member
    exact linked.value (constants constant member)
  · intro function member
    obtain ⟨source, _, rfl⟩ := List.mem_map.mp member
    exact source.wellTyped linked

def entryValid (program : Core.Program) (entry : FunctionId) : Bool :=
  match program.function? entry with
  | some function => function.parameters.isEmpty && function.body.isSome
  | none => false

/-- A successfully linked program carries no copy of its Core syntax or
    per-function typing proofs. `core` and `wellTyped` are shared projections. -/
structure Program where
  signature : Signature
  functions : List (Function signature)
  headers : functions.map (FunctionType.ofCore ∘ Function.erase) = signature.functions
  constants : ∀ constant ∈ signature.constants, ConstantWellTyped signature.declarations constant
  entry : FunctionId
  validEntry : entryValid (assemble signature functions) entry = true

def Program.core (program : Program) : Core.Program := assemble program.signature program.functions

theorem Program.wellTyped (program : Program) : ProgramWellTyped program.core :=
  assemble_wellTyped program.signature program.functions program.headers program.constants

def link (signature : Signature) (functions : List (Function signature)) (entry : FunctionId)
    (headers : functions.map (FunctionType.ofCore ∘ Function.erase) = signature.functions)
    (constants : ∀ constant ∈ signature.constants, ConstantWellTyped signature.declarations constant)
    (validEntry : entryValid (assemble signature functions) entry = true) : Program :=
  ⟨signature, functions, headers, constants, entry, validEntry⟩

end Lanius.TypedIR.Intrinsic
