import Lanius.Extraction.CompactOutput.Nodes.Source
import Lanius.FunctionalViewCoreSimulation

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.FunctionalView.Core

def argumentsValues (input offsets output : Value) (length nodes count capacity position : Int) : List Value :=
  [input, .signed .i32 length, offsets, .signed .i32 nodes, .signed .i32 count,
    output, .signed .i32 capacity, .signed .i32 position]

def bindings (input offsets output : Value) (length nodes count capacity position : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 8 => (argumentsValues input offsets output length nodes count capacity position).get index)

end Lanius.Extraction.CompactOutput.Nodes
