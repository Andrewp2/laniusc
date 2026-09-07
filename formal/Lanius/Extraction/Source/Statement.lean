import Lanius.Core

namespace Lanius.Extraction.Source

open Lanius.Core

/-- A matched source statement with its recovered bindings and exact shape. -/
structure CheckedStatement {α : Type} (shape : α → Stmt) (statement : Stmt) where
  locals : α
  exactSource : statement = shape locals

inductive StatementIn (statement : Stmt) : Stmt → Prop where
  | here : StatementIn statement statement
  | sequenceLeft : StatementIn statement first → StatementIn statement (.sequence first second)
  | sequenceRight : StatementIn statement second → StatementIn statement (.sequence first second)
  | letLocal : StatementIn statement body → StatementIn statement (.letLocal localId type value body)
  | letUninitialized : StatementIn statement body → StatementIn statement (.letUninitialized localId type body)
  | thenBranch : StatementIn statement body → StatementIn statement (.ifThenElse condition body other)
  | elseBranch : StatementIn statement body → StatementIn statement (.ifThenElse condition other body)
  | whileBody : StatementIn statement body → StatementIn statement (.whileLoop condition body)
  | forValuesBody : StatementIn statement body → StatementIn statement (.forValues localId values body)
  | forRangeBody : StatementIn statement body → StatementIn statement (.forRange localId start stop inclusive body)

structure LocatedStatement {α : Type} (shape : α → Stmt) (body : Stmt) where
  locals : α
  occurs : StatementIn (shape locals) body

/-- Share the source traversal between algorithm-specific proof-producing
matchers without copying the enclosing checked function into new declarations. -/
def findStatement? {α : Type} (shape : α → Stmt)
    (check : (statement : Stmt) → Option (CheckedStatement shape statement))
    (body : Stmt) : Option (LocatedStatement shape body) :=
  match check body with
  | some checked => some ⟨checked.locals, by
      rcases checked with ⟨locals, exactSource⟩
      dsimp
      rw [exactSource]
      exact .here⟩
  | none =>
      match body with
      | .sequence first second =>
          ((findStatement? shape check first).map fun found =>
            ⟨found.locals, .sequenceLeft found.occurs⟩).orElse fun _ =>
              (findStatement? shape check second).map fun found =>
                ⟨found.locals, .sequenceRight found.occurs⟩
      | .letLocal _ _ _ rest =>
          (findStatement? shape check rest).map fun found => ⟨found.locals, .letLocal found.occurs⟩
      | .letUninitialized _ _ rest =>
          (findStatement? shape check rest).map fun found => ⟨found.locals, .letUninitialized found.occurs⟩
      | .ifThenElse _ first second =>
          ((findStatement? shape check first).map fun found =>
            ⟨found.locals, .thenBranch found.occurs⟩).orElse fun _ =>
              (findStatement? shape check second).map fun found =>
                ⟨found.locals, .elseBranch found.occurs⟩
      | .whileLoop _ rest =>
          (findStatement? shape check rest).map fun found => ⟨found.locals, .whileBody found.occurs⟩
      | .forValues _ _ rest =>
          (findStatement? shape check rest).map fun found => ⟨found.locals, .forValuesBody found.occurs⟩
      | .forRange _ _ _ _ rest =>
          (findStatement? shape check rest).map fun found => ⟨found.locals, .forRangeBody found.occurs⟩
      | _ => none

end Lanius.Extraction.Source
