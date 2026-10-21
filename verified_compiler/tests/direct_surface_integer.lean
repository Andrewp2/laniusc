import verified_compiler.tests.direct_surface_ir
import verified_compiler.tests.direct_output_signed

namespace SurfaceIntegerProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open IRBuilderNavigationProof SurfaceBooleanProof

def integerEvent (value : Int) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionInteger» [.signed .i32 value]

/-- The actual integer atom reads the IR payload, not a separately supplied
    printer value, and reuses the complete signed writer contract. -/
theorem actualAtom (context : Context state) (tree : Ready region state) (value : Int)
    (representation : context.tree = tree.value) (inside : index < region.count)
    (event : region.events index = integerEvent value)
    (canonical : -2147483648 ≤ value ∧ value < 2147483648)
    (room : context.position + (OutputSignedProof.bytes value).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.atomCall index)
      (.signed .i32 (context.position + (OutputSignedProof.bytes value).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (OutputSignedProof.bytes value) := by
  have formed := environment.formed
  apply actualSelectedAtom context tree (integerEvent value) representation inside event
    (bindings := [(armBinding 2, .signed .i32 value)]) (by rfl) environment.formed
  let branch := (context.atomScope tree index).bindLocals [(armBinding 2, .signed .i32 value)]
  let buffer : OutputNaturalProof.Buffer branch := { context.toBuffer with readable := context.readable }
  have writer := OutputSignedProof.actualCall_formats buffer value canonical room
    (by core_formed) environment.noViews environment.below environment.unique
  core_writer_expr

#print axioms actualAtom

end SurfaceIntegerProof
