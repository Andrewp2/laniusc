import Lanius.Extraction.CanonicalTokens.Dispatch.Call

namespace Lanius.Extraction.CanonicalTokens.Kind

open Lanius.Core

def arguments : List Expr := [.local 0, .local 2, .local 3]

def condition (identifier : ConstantId) : Expr := .binary .equal (.local 1) (.constant identifier)

def body (keyword : FunctionId) (identifier : ConstantId) : Stmt :=
  .sequence (.ifThenElse (condition identifier)
    (.sequence (.returnValue (some (.call keyword arguments))) .skip) .skip)
    (.sequence (.returnValue (some (.local 1))) .skip)

def sourceFunction (id keyword : FunctionId) (identifier : ConstantId) : Function := {
  id
  parameters := [(0, .slice (.scalar (.signed .i32))), (1, .scalar (.signed .i32)),
    (2, .scalar (.signed .i32)), (3, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some (body keyword identifier)
}

structure Checked (program : Program) (functionId keywordId matcher : FunctionId) where
  keyword : Dispatch.CheckedFunction program keywordId matcher
  identifier : ConstantId
  identifierFound : program.constant? identifier = some {
    id := identifier, type := .scalar (.signed .i32), value := .signed .i32 1 }
  found : program.function? functionId = some (sourceFunction functionId keywordId identifier)

def check? (program : Program) (functionId : FunctionId)
    {keywordId matcher : FunctionId} (keyword : Dispatch.CheckedFunction program keywordId matcher) :
    Option (Checked program functionId keywordId matcher) := do
  match found : program.function? functionId with
  | none => none
  | some function =>
      let some (.sequence (.ifThenElse (.binary .equal _ (.constant identifier)) _ _) _) := function.body | none
      let same ← Equality.function? function (sourceFunction functionId keywordId identifier)
      match constantFound : program.constant? identifier with
      | none => none
      | some constant =>
          let sameConstant ← Equality.constant? constant {
            id := identifier, type := .scalar (.signed .i32), value := .signed .i32 1 }
          pure ⟨keyword, identifier, constantFound.trans (congrArg some sameConstant.equal),
            found.trans (congrArg some same.equal)⟩

end Lanius.Extraction.CanonicalTokens.Kind
