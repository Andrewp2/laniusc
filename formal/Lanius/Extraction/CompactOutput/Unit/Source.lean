import Lanius.Extraction.CompactOutput.Source

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Extraction.Source

structure Symbols where
  word : FunctionId
  bytes : FunctionId
  tokens : FunctionId
  semantic : FunctionId
  nodes : FunctionId

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, .slice i32), (3, i32), (4, .slice i32), (5, i32),
    (6, i32), (7, .slice i32), (8, i32), (9, i32), (10, .slice i32), (11, i32),
    (12, .slice i32), (13, i32), (14, .slice i32), (15, i32), (16, .slice i32), (17, i32), (18, i32)]

def guard : Expr := binary .logicalOr
  (binary .logicalOr (binary .lessEqual (read 1) negativeOne) (binary .lessEqual (read 3) negativeOne))
  (binary .lessEqual (read 15) (number 0))
def wordCall (symbols : Symbols) (cursor value : Expr) : Expr :=
  .call symbols.word [read 16, read 17, cursor, value]
def bytesCall (symbols : Symbols) (input length : VarId) : Expr :=
  .call symbols.bytes [read input, read length, read 16, read 17, read 19]
def tokensCall (symbols : Symbols) (input length count : VarId) : Expr :=
  .call symbols.tokens [read input, read length, read count, read 3, read 16, read 17, read 19]
def semanticCall (symbols : Symbols) : Expr :=
  .call symbols.semantic [read 10, read 11, read 9, read 16, read 17, read 19]
def nodesCall (symbols : Symbols) : Expr :=
  .call symbols.nodes [read 12, read 13, read 14, read 15, read 9, read 16, read 17, read 19]
def assignThen (call : Expr) (tail : Stmt) : Stmt :=
  .sequence (.expression (.assign .set (.local 19) call)) tail
def tail (symbols : Symbols) : Stmt :=
  assignThen (bytesCall symbols 0 1)
    (assignThen (wordCall symbols (read 19) (read 3))
      (assignThen (bytesCall symbols 2 3)
        (assignThen (wordCall symbols (read 19) (read 6))
          (assignThen (tokensCall symbols 4 5 6)
            (assignThen (wordCall symbols (read 19) (read 9))
              (assignThen (tokensCall symbols 7 8 9)
                (assignThen (semanticCall symbols)
                  (assignThen (wordCall symbols (read 19) (read 15))
                    (returned (nodesCall symbols))))))))))
def body (symbols : Symbols) : Stmt :=
  .sequence (.ifThenElse guard (returned negativeOne) .skip)
    (.letLocal 19 i32 (wordCall symbols (read 18) (read 1)) (tail symbols))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts) (symbols : Symbols) :=
  CheckedInternal program ["verified", "compact_artifact_output"] "emit_unit" parameters i32 (body symbols)
def check? (program : CoreSynthesis.Program.CheckedProgram artifacts) (symbols : Symbols) :
    Option (Checked program symbols) :=
  checkInternal? program ["verified", "compact_artifact_output"] "emit_unit" parameters i32 (body symbols)

end Lanius.Extraction.CompactOutput.Unit
