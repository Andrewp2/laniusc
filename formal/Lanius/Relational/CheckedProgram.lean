import Lanius.Extraction.CompleteChecker
import Lanius.Typing

namespace Lanius.Relational

open Lanius.Core
open Lanius.Extraction
open Lanius.Typing

/-! # Checked-program facade

This module is deliberately a projection of the existing complete artifact
checker.  It does not introduce another acceptance path.  Function references
carry the lookup, body-presence, and signature facts that algorithm proofs used
to recover repeatedly from numeric identifiers.
-/

/-- Decode the Core program selected by the existing pack merger.  A
`CheckedProgram` below also carries the complete pack certificate, which rules
out the fallback branch for accepted packs. -/
def decodeMergedProgram (pack : ArtifactPack) : Program :=
  match ArtifactPackChecker.mergeCorePrograms? pack.units with
  | some wire => CoreDecode.program wire
  | none => {}

/-- One accepted artifact pack together with its authoritative Core program. -/
structure CheckedProgram where
  pack : ArtifactPack
  checked : CompleteChecker.CheckedPack pack
  core : Program
  core_eq : core = decodeMergedProgram pack

structure FnSignature where
  arguments : List Ty
  result : Ty
deriving Repr

/-- A one-based source position. `offset` is optional because older checked
artifacts record line/column identity without retaining a byte offset. -/
structure SourcePosition where
  line : Nat
  column : Nat
  offset : Option Nat := none
deriving DecidableEq, Repr

structure SourceSpan where
  start : SourcePosition
  stop : SourcePosition
deriving DecidableEq, Repr

/-- Stable source-facing identity used for diagnostics and generated handles.
It is not used as the execution key; the checked `Function` remains
authoritative.  Existing generated handles may omit `span`; new extraction
paths can populate it without changing the semantic lookup key. -/
structure SourceIdentity where
  path : String
  name : String
  span : Option SourceSpan := none
deriving DecidableEq, Repr

/-- A Core value paired with evidence that it denotes the type carried by a
typed function signature.  The value remains the existing authoritative Core
value; this is only a proof-facing wrapper. -/
structure CheckedProgram.TypedValue
    (program : CheckedProgram) (type : Ty) where
  value : Value
  typed : ValueHasType program.core value type

/-- Signature-indexed argument tuples.  This replaces positional recovery
from an untyped `List Value` in clients of the facade. -/
inductive CheckedProgram.Args (program : CheckedProgram) : List Ty → Type where
  | nil : program.Args []
  | cons (head : program.TypedValue type) (tail : program.Args types) :
      program.Args (type :: types)

def CheckedProgram.Args.values {program : CheckedProgram} :
    {types : List Ty} → program.Args types → List Value
  | [], .nil => []
  | _ :: _, .cons head tail => head.value :: tail.values

theorem CheckedProgram.Args.values_typed {program : CheckedProgram} :
    {types : List Ty} → (arguments : program.Args types) →
      ValuesHaveTypes program.core arguments.values types
  | [], .nil => .nil
  | _ :: _, .cons head tail => .cons head.typed tail.values_typed

/-- A body-bearing, signature-indexed function selected from a checked
program. -/
structure CheckedProgram.FnRef
    (program : CheckedProgram) (signature : FnSignature) where
  function : Function
  body : Stmt
  found : program.core.function? function.id = some function
  bodyFound : function.body = some body
  parameterTypes : function.parameters.map Prod.snd = signature.arguments
  resultType : function.returnType = signature.result
  source : SourceIdentity

end Lanius.Relational
