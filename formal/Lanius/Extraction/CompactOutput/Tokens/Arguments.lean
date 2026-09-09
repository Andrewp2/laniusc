import Lanius.Extraction.CompactOutput.Tokens.Source
import Lanius.FunctionalViewCoreSimulation

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.FunctionalView.Core

def argumentsValues (input output : Value) (length count sourceLength capacity position : Int) : List Value :=
  [input, .signed .i32 length, .signed .i32 count, .signed .i32 sourceLength, output, .signed .i32 capacity, .signed .i32 position]

def bindings (input output : Value) (length count sourceLength capacity position : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 7 => (argumentsValues input output length count sourceLength capacity position).get index)

end Lanius.Extraction.CompactOutput.Tokens

