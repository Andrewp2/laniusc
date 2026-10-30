import Lanius.Mini.Reading.Det.Decls

/-! # The reading is deterministic, F1: lowering types and their instances -/

namespace Lanius.Mini.Reading

open Lanius.Mini

theorem tyRs_unique {env : FrontEnv} {ts : List CTree} {a b : List Ty}
    (h₁ : ListRel (TyR env) ts a) (h₂ : ListRel (TyR env) ts b) : a = b :=
  listRel_unique (R := TyR env) (fun _ _ _ x y => tyR_unique x y) h₁ h₂

theorem tyRss_unique {env : FrontEnv} {ts : List (List CTree)} {a b : List (List Ty)}
    (h₁ : ListRel (ListRel (TyR env)) ts a) (h₂ : ListRel (ListRel (TyR env)) ts b) : a = b :=
  listRel_unique (R := ListRel (TyR env)) (fun _ _ _ x y => tyRs_unique x y) h₁ h₂

theorem fieldTys_unique {decls : Decls} {d : Nat} {args a b : List Ty}
    (h₁ : FieldTys decls d args a) (h₂ : FieldTys decls d args b) : a = b := by
  obtain ⟨t, e, r⟩ := h₁
  obtain ⟨t', e', r'⟩ := h₂
  rw [e] at e'
  cases e'
  exact tyRs_unique r r'

theorem payloadTys_unique {decls : Decls} {d : Nat} {args : List Ty} {a b : List (List Ty)}
    (h₁ : PayloadTys decls d args a) (h₂ : PayloadTys decls d args b) : a = b := by
  obtain ⟨t, e, r⟩ := h₁
  obtain ⟨t', e', r'⟩ := h₂
  rw [e] at e'
  cases e'
  exact tyRss_unique r r'

theorem isEnum_clash {decls : Decls} {d : Nat} {t t' : TypeDecl} (e : decls.types[d]? = some t)
    (e' : decls.types[d]? = some t') (f : t.isEnum = false) (g : t'.isEnum = true) : False := by
  rw [e] at e'
  cases e'
  rw [f] at g
  cases g

mutual
theorem lowerR_unique {decls : Decls} {table : List Inst} :
    ∀ {t : Ty} {a b : SrcType}, LowerR decls table t a → LowerR decls table t b → a = b
  | _, _, _, .i32, .i32 => rfl
  | _, _, _, .bool, .bool => rfl
  | _, _, _, .uint, .uint => rfl
  | _, _, _, .ptr, .ptr => rfl
  | _, _, _, .isize, .isize => rfl
  | _, _, _, .slice e, .slice e' => by rw [lowerR_unique e e']
  | _, _, _, .struct _ _ k f l, .struct _ _ k' f' l' => by
    rw [(firstWith_unique k k').1]
    rw [fieldTys_unique f f'] at l
    rw [lowerList_unique l l']
  | _, _, _, .struct e n .., .enum e' n' .. => (isEnum_clash e e' n n').elim
  | _, _, _, .enum e n .., .struct e' n' .. => (isEnum_clash e' e n' n).elim
  | _, _, _, .enum _ _ k p l, .enum _ _ k' p' l' => by
    rw [(firstWith_unique k k').1]
    rw [payloadTys_unique p p'] at l
    rw [lowerVariants_unique l l']

theorem lowerList_unique {decls : Decls} {table : List Inst} :
    ∀ {ts : List Ty} {a b : List SrcType}, LowerList decls table ts a → LowerList decls table ts b → a = b
  | _, _, _, .nil, .nil => rfl
  | _, _, _, .cons l r, .cons l' r' => by rw [lowerR_unique l l', lowerList_unique r r']

theorem lowerVariants_unique {decls : Decls} {table : List Inst} :
    ∀ {ts : List (List Ty)} {a b : List (List SrcType)},
      LowerVariants decls table ts a → LowerVariants decls table ts b → a = b
  | _, _, _, .nil, .nil => rfl
  | _, _, _, .cons l r, .cons l' r' => by rw [lowerList_unique l l', lowerVariants_unique r r']
end

mutual
theorem tyInsts_unique {decls : Decls} : ∀ {t : Ty} {a b : List Inst}, TyInsts decls t a → TyInsts decls t b → a = b
  | _, _, _, .i32, .i32 => rfl
  | _, _, _, .bool, .bool => rfl
  | _, _, _, .uint, .uint => rfl
  | _, _, _, .ptr, .ptr => rfl
  | _, _, _, .isize, .isize => rfl
  | _, _, _, .slice e, .slice e' => tyInsts_unique e e'
  | _, _, _, .struct _ _ f r, .struct _ _ f' r' => by
    rw [fieldTys_unique f f'] at r
    rw [tysInsts_unique r r']
  | _, _, _, .struct e n .., .enum e' n' .. => (isEnum_clash e e' n n').elim
  | _, _, _, .enum e n .., .struct e' n' .. => (isEnum_clash e' e n' n).elim
  | _, _, _, .enum _ _ p r, .enum _ _ p' r' => by
    rw [payloadTys_unique p p'] at r
    rw [tysInsts_unique r r']

theorem tysInsts_unique {decls : Decls} : ∀ {ts : List Ty} {a b : List Inst},
    TysInsts decls ts a → TysInsts decls ts b → a = b
  | _, _, _, .nil, .nil => rfl
  | _, _, _, .cons l r, .cons l' r' => by rw [tyInsts_unique l l', tysInsts_unique r r']
end

end Lanius.Mini.Reading
