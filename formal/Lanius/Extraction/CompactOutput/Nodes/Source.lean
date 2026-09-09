import Lanius.Extraction.CompactOutput.Nodes.Validate
import Lanius.Extraction.CompactOutput.Nodes.Write

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Extraction.Source

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, .slice i32), (3, i32), (4, i32),
    (5, .slice i32), (6, i32), (7, i32)]
def failureGuard : Expr := binary .lessEqual (read 8) negativeOne
def childCondition : Expr := binary .notEqual (read 13) (read 12)
def childIncrement : Expr := .assign .add (.local 13) (number 1)
def childStep (wordId : FunctionId) (tokenTag stateTag : Lanius.ConstantId) : Stmt :=
  .letLocal 14 i32 childSlot (.letLocal 15 i32 tagRead (.letLocal 16 i32 payloadRead
    (.sequence (.ifThenElse payloadGuard (returned negativeOne) .skip)
      (.sequence (validationBranch tokenTag stateTag)
        (.sequence (.expression (tagWrite wordId))
          (.sequence (.expression (payloadWrite wordId))
            (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
              (.sequence (.expression childIncrement) .skip))))))))
def childLoop (wordId : FunctionId) (tokenTag stateTag : Lanius.ConstantId) : Stmt :=
  .whileLoop childCondition (childStep wordId tokenTag stateTag)
def recordGuard : Expr := binary .logicalOr
  (binary .logicalOr (binary .lessEqual (read 10) negativeOne)
    (.unary .logicalNot (binary .lessEqual (read 10) (read 1))))
  (binary .lessEqual (binary .subtract (read 1) (read 10)) (number 3))
def childrenGuard : Expr := binary .logicalOr
  (binary .logicalOr (binary .lessEqual (read 11) negativeOne) (binary .lessEqual (read 12) negativeOne))
  (.unary .logicalNot (binary .lessEqual (read 12)
    (binary .divide (binary .subtract (binary .subtract (read 1) (read 10)) (number 4)) (number 3))))
def recordRead (field : Nat) : Expr := .index (read 0) (binary .add (read 10) (number field))
def headerWrite (wordId : FunctionId) (value : Expr) : Expr := Word.assignCall wordId 8 (read 5) (read 6) value
def condition : Expr := binary .notEqual (read 9) (read 3)
def increment : Expr := .assign .add (.local 9) (number 1)
def step (wordId : FunctionId) (tokenTag stateTag : Lanius.ConstantId) : Stmt :=
  .letLocal 10 i32 (.index (read 2) (read 9))
    (.sequence (.ifThenElse recordGuard (returned negativeOne) .skip)
      (.letLocal 11 i32 (.index (read 0) (read 10)) (.letLocal 12 i32 (recordRead 3)
        (.sequence (.ifThenElse childrenGuard (returned negativeOne) .skip)
          (.sequence (.expression (headerWrite wordId (read 11)))
            (.sequence (.expression (headerWrite wordId (recordRead 1)))
              (.sequence (.expression (headerWrite wordId (recordRead 2)))
                (.sequence (.expression (headerWrite wordId (read 12)))
                  (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
                    (.letLocal 13 i32 (number 0)
                      (.sequence (childLoop wordId tokenTag stateTag)
                        (.sequence (.expression increment) .skip))))))))))))
def entryGuard : Expr := binary .logicalOr (binary .lessEqual (read 3) negativeOne)
  (binary .lessEqual (read 4) negativeOne)
def body (wordId : FunctionId) (tokenTag stateTag : Lanius.ConstantId) : Stmt :=
  .sequence (.ifThenElse entryGuard (returned negativeOne) .skip)
    (.letLocal 8 i32 (read 7) (.letLocal 9 i32 (number 0)
      (.sequence (.whileLoop condition (step wordId tokenTag stateTag)) (returned (read 8)))))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program)
    (word : Word.Checked program byte digit) (tokenTag stateTag : Lanius.ConstantId) :=
  CheckedInternal program ["verified", "compact_artifact_output"] "nodes" parameters i32
    (body word.source.function.id tokenTag stateTag)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program)
    (word : Word.Checked program byte digit) (tokenTag stateTag : Lanius.ConstantId) :
    Option (Checked program byte digit word tokenTag stateTag) :=
  checkInternal? program ["verified", "compact_artifact_output"] "nodes" parameters i32
    (body word.source.function.id tokenTag stateTag)

end Lanius.Extraction.CompactOutput.Nodes
