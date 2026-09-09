import Lanius.Extraction.CompactOutput.Assignments.Source
import Lanius.FunctionalViewCoreSimulation

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Core Lanius.FunctionalView.Core

def argumentsValues (input output : Value) (length count capacity position : Int) : List Value :=
  [input, .signed .i32 length, .signed .i32 count, output, .signed .i32 capacity, .signed .i32 position]

def bindings (input output : Value) (length count capacity position : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 6 => (argumentsValues input output length count capacity position).get index)

end Lanius.Extraction.CompactOutput.Assignments
