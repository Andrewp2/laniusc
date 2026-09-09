import Lanius.Extraction.CompactOutput.Tokens.Source

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Lexer Lanius.Extraction.CanonicalTokens.CanonicalizeModel

def rowState (before : State) (index : Nat) : State :=
  before.bindLocal 9 (.signed .i32 (3 * index : Nat))
def startState (before : State) (index : Nat) (token : RawToken) : State :=
  (rowState before index).bindLocal 10 (.signed .i32 token.start)
def fieldsState (before : State) (index : Nat) (token : RawToken) : State :=
  (startState before index token).bindLocal 11 (.signed .i32 token.finish)

/-- Derive each initializer in execution order; binding earlier temporaries
preserves the frontend's input prefix and the row address. -/
theorem initialize_fields (program : Program) (tokens : List RawToken) (index : Nat)
    (wellFormed : StateWellFormed before)
    (input : I32PrefixLocal before 0 inputCell (encodeTokens tokens))
    (indexRead : before.local? 8 = some (.signed .i32 index))
    (bound : index < tokens.length) (sizeFit : 3 * tokens.length ≤ 2147483647) :
    Evaluates program before rowIndex (.signed .i32 (3 * index : Nat)) before ∧
    Evaluates program (rowState before index) startRead (.signed .i32 tokens[index].start)
      (rowState before index) ∧
    Evaluates program (startState before index tokens[index]) finishRead
      (.signed .i32 tokens[index].finish) (startState before index tokens[index]) ∧
    StateWellFormed (fieldsState before index tokens[index]) ∧
    (fieldsState before index tokens[index]).local? 10 = some (.signed .i32 tokens[index].start) ∧
    (fieldsState before index tokens[index]).local? 11 = some (.signed .i32 tokens[index].finish) ∧
    Evaluates program (fieldsState before index tokens[index]) kindRead
      (.signed .i32 tokens[index].kind.gpuCode) (fieldsState before index tokens[index]) ∧
    I32PrefixLocal (fieldsState before index tokens[index]) 0 inputCell (encodeTokens tokens) := by
  have rowWF : StateWellFormed (rowState before index) :=
    bindLocal_preserves_well_formed _ _ _ wellFormed
  have rowInput := input.bindLocal wellFormed 9 (.signed .i32 (3 * index : Nat)) (by decide)
  have rowLocal : (rowState before index).local? 9 = some (.signed .i32 (3 * index : Nat)) :=
    bindLocal_finds_local before _ _ wellFormed
  have startWF : StateWellFormed (startState before index tokens[index]) :=
    bindLocal_preserves_well_formed _ _ _ rowWF
  have startInput := rowInput.bindLocal rowWF 10 (.signed .i32 tokens[index].start) (by decide)
  have startRow : (startState before index tokens[index]).local? 9 = some (.signed .i32 (3 * index : Nat)) :=
    (bindLocal_preserves_other_local rowWF (by decide : (10 : VarId) ≠ 9)).trans rowLocal
  have finalWF : StateWellFormed (fieldsState before index tokens[index]) :=
    bindLocal_preserves_well_formed _ _ _ startWF
  have finalInput := startInput.bindLocal startWF 11 (.signed .i32 tokens[index].finish) (by decide)
  have finalRow : (fieldsState before index tokens[index]).local? 9 = some (.signed .i32 (3 * index : Nat)) :=
    (bindLocal_preserves_other_local startWF (by decide : (11 : VarId) ≠ 9)).trans startRow
  exact ⟨row_index program index tokens.length bound sizeFit indexRead,
    (read_row program tokens index rowInput rowLocal bound sizeFit).2.1,
    (read_row program tokens index startInput startRow bound sizeFit).2.2,
    finalWF,
    (bindLocal_preserves_other_local startWF (by decide : (11 : VarId) ≠ 10)).trans
      (bindLocal_finds_local (rowState before index) _ _ rowWF),
    bindLocal_finds_local (startState before index tokens[index]) _ _ startWF,
    (read_row program tokens index finalInput finalRow bound sizeFit).1,
    finalInput⟩

end Lanius.Extraction.CompactOutput.Tokens
