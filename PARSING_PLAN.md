# PARSING_PLAN.md
Lanius parsing+lexing plan for **LLP(1,1)** with Rust-like surface syntax and **function calls using `()`** (arrays/indexing use `[]`). We keep the GPU-first pipeline from `LEXING.md` and add one **parallel retagging** pass that separates grouping `()` from call `()` and array literal `[]` from indexing `[]`. With those tokens disambiguated, the grammar remains LLP(1,1) as in the papers.

---

## 0) Goals (and non-goals for MVP)

**Goals**
- Parenthesized **function calls**: `foo(a, b)` and also `(foo)(a)`.
- Standard arithmetic precedence: `a + b * c`, grouping with `()`.
- Arrays with `[]`, indexing with `[]` after a primary.
- Items: `fn`, `struct`, `trait`, visibility `pub|priv`, `let`/`var`, type annotations `:`.
- **Strings** as tokens (simple `"..."` MVP).
- Keep the parser **LLP(1,1)** to run in parallel on GPU as per the “ParallelLLParsing” approach.

**Non-goals (MVP)**
- No casts via `Type(expr)` (we’ll use `expr as Type` later).
- No generic arguments in expression positions (only in type positions).
- No full pattern syntax (just `Ident` for `Pattern` initially).

---

## 1) Pipeline overview (GPU-first)

We extend the existing lex pipeline (`LEXING.md`) with one extra, fully parallel pass:

1. **Raw lex (GPU)** — already implemented:
   - Streaming DFA → tokens with kinds, spans.
   - Filter whitespace/comments.

2. **Parallel retagging (GPU)** — **new**:
   - Compute, for each token, the **previous significant token** index via an exclusive prefix scan.
   - Retag punctuation based on **local, 1-token look-back category**:
     - `LPAREN`  → `CALL_LPAREN` iff **prev** ∈ { `IDENT`, `INT`, `STRING`, `RPAREN`, `RBRACKET`, `RBRACE` } (i.e. previous token **ends a Primary**) ; otherwise `GROUP_LPAREN`.
     - `LBRACKET`→ `INDEX_LBRACKET` iff **prev** ends a Primary; otherwise `ARRAY_LBRACKET`.
   - This pass is **O(n)** work, **O(log n)** depth (prefix scans + table lookups), identical cost class to lex.

3. **(Optional) Keywordization (GPU/CPU)** — small:
   - Either keep keywords as `IDENT` with known lexemes (`"fn"`, `"struct"`, …) or tag them to dedicated tokens. Parser code supports either.

4. **LLP(1,1) parse (GPU)**:
   - With `CALL_LPAREN` / `GROUP_LPAREN` and `INDEX_LBRACKET` / `ARRAY_LBRACKET`, the grammar has unique FIRST sets at each decision site. We follow the “ParallelLLParsing” scheme: segment by bracket structure, parse LARs independently, merge.

> **Why this stays parallel:** Retagging only needs “previous significant token kind”. That’s obtainable with a single exclusive prefix **max** (or carry) over positions marking “is significant here?”, then a gather to read the prior kind, then a constant-time retag table. No serial dependence.

---

## 2) Token disambiguation rules

We rely on the notion “**token that ends a Primary**”:

```

ENDS\_PRIMARY := { IDENT, INT, STRING, RPAREN, RBRACKET, RBRACE }

```

**Retag rules (applied to the raw token stream, after filtering trivia):**

| Raw token  | Condition on previous sig. token | Retagged token   |
| ---------- | -------------------------------- | ---------------- |
| `LPAREN`   | prev ∈ ENDS_PRIMARY              | `CALL_LPAREN`    |
| `LPAREN`   | else                             | `GROUP_LPAREN`   |
| `LBRACKET` | prev ∈ ENDS_PRIMARY              | `INDEX_LBRACKET` |
| `LBRACKET` | else                             | `ARRAY_LBRACKET` |

**Trailing commas** remain orthogonal; parser accepts them where listed.

> This mirrors what hand-written Pratt/recursive-descent parsers do, but we encode it in a **purely local token transform** that’s easy to parallelize.

---

## 3) Grammar (MVP) that the LLP(1,1) parser sees

Exactly the `grammar/lanius.ebnf` you added, with the understanding that `Call` and `Array`/`Index` consume the **retagged** tokens:

```ebnf
(* excerpt; see full file in grammar/lanius.ebnf *)

Postfix         = Primary { Call | Index } ;

Call            = CALL_LPAREN [ ArgList [ "," ] ] ")" ;
Index           = INDEX_LBRACKET Expr "]" ;

Primary         = Int
                | String
                | Ident
                | Group
                | Block
                | Array ;

Group           = GROUP_LPAREN Expr ")" ;
Array           = ARRAY_LBRACKET [ Expr { "," Expr } [ "," ] ] "]" ;
```

**LLP(1,1) sanity notes**

* At a `Postfix` extension point, the next token is one of `{ CALL_LPAREN, INDEX_LBRACKET }` or something else. That choice is unique with 1 lookahead.
* `Group` vs `Call` ambiguity is gone because they are different terminals.
* Arrays vs indexing disambiguated likewise.
* Restricting generics to **Type** keeps `<` vs `Lt` unambiguous in expressions.
* Decls (`let`, `var`, `fn`, `struct`, `trait`) start with reserved words, so statement vs expr is trivial.

---

## 4) Correctness sketch

* The **only** hard ambiguity for LLP(1,1) with Rusty surface is `(` and `[` playing double roles. The retag pass removes that ambiguity with **local** information that does **not** require parsing state.
* FIRST/FOLLOW conflicts at key nonterminals vanish:

  * `Primary` vs `Postfix` extension: FIRST(Postfix-tail) = `{ CALL_LPAREN, INDEX_LBRACKET }`, disjoint from FIRST of others.
  * `Group` vs `Call` separated at the lexical level.
  * Compare/Add/Mul ladders are standard LL.
* This places us squarely within the “LLP(1,1) with bracket partitioning” model used to parallelize LL parsing on GPU.

---

## 5) GPU implementation details for the retag pass

**Inputs:** compacted token arrays from the lexer:

```
kind[i] : u16
start[i], len[i] : u32
```

**Step A: previous significant index**

* Build `is_sig[i]` (everything except filtered trivia).
* Build `idx[i] = i` if `is_sig[i]` else `-1`.
* Run an **exclusive prefix scan carrying last non-(-1)** → `prev_idx[i]`.

  * Implementation: prefix **max** over monotone-increasing `idx` works.
* Define `prev_kind[i] = (prev_idx[i] >= 0 ? kind[prev_idx[i]] : SENTINEL)`.

**Step B: retag**

* Table-driven:

  ```
  ends_primary = bitset on {IDENT, INT, STRING, RPAREN, RBRACKET, RBRACE}
  if kind[i]==LPAREN:
      kind[i] = (ends_primary[prev_kind[i]] ? CALL_LPAREN : GROUP_LPAREN)
  if kind[i]==LBRACKET:
      kind[i] = (ends_primary[prev_kind[i]] ? INDEX_LBRACKET : ARRAY_LBRACKET)
  ```
* All threads independent; no divergence besides two ifs.

**Artifacts to add (suggested):**

* `shaders/lexer/retag_calls_and_arrays.slang`
* `src/lexer/gpu/passes/retag_calls_and_arrays.rs` (host dispatch + tests)

We can reuse the existing scan utilities (see `scan_*` Slang kernels already present).

---

## 6) Strings (MVP)

* Tokenize simple double-quoted strings with escapes. Keep them **atomic** in the lexer DFA (already compatible with streaming DFA).
* Strings appear in `Primary` and therefore also **end a Primary** → they enable call/index right after, e.g. `"hello"(…)` is **legal** only if we *want* to allow calling string-valued primaries. For MVP, that’s allowed by grammar but can be rejected in type checking if undesired.

---

## 7) Examples

```lan
pub fn mul_add(x: Int, y: Int, z: Int) -> Int {
    (x * y) + z;
}

let a: Int = 2;
let b: Int = 3;
let c: Int = 4;

let m0: Int = a + b * c;        // a + (b * c)
let m1: Int = (a + b) * c;

let r0: Int = mul_add(a, b, c);
let r1: Int = (mul_add)(1, 2, 3);

let xs: Array<Int> = [1, 2, 3,];
let first: Int = xs[0];
let r2: Int = mul_add(first, 10, 1);
```

**Token shapes after retag (snippets):**

* `mul_add ( a , b , c )` → `IDENT CALL_LPAREN IDENT , IDENT , IDENT )`
* `( mul_add ) ( 1 , 2 , 3 )` → `GROUP_LPAREN IDENT ) CALL_LPAREN INT , INT , INT )`
* `xs [ 0 ]` → `IDENT INDEX_LBRACKET INT ]`
* `[ 1 , 2 , 3 , ]` → `ARRAY_LBRACKET INT , INT , INT , ]`

---

## 8) Work items

* [ ] Add token kinds: `CALL_LPAREN`, `GROUP_LPAREN`, `INDEX_LBRACKET`, `ARRAY_LBRACKET`.
* [ ] Emit them in a **retag** GPU pass (not in the raw DFA).
* [ ] Wire pass into `src/lexer/gpu/mod.rs` pipeline; expose CPU fallback.
* [ ] Update EBNF comments to reference retagged tokens (the structure already matches).
* [ ] Parser: consume new tokens; keep LLP(1,1) driver.
* [ ] Tests:

  * [ ] Golden token streams around tricky punctuation.
  * [ ] Parsing samples (`()` calls, `[]` arrays/index, nested cases, trailing commas).
  * [ ] Property tests comparing CPU/GPU parser outputs.

---

## 9) Future compatibility

* **Generics in expressions** (`foo::<T>(x)`): introduce a tiny **angle-bracket retag** pass (similar idea), or require `::<` after `IDENT` only; still local and parallel.
* **Casts**: prefer `expr as Type` to avoid `Type(expr)` ambiguity entirely.
* **Keywords**: can be hard-tagged in the retag pass (IDENT → KW\_FN, …) to simplify parse tables; optional.

---

### TL;DR

Keep `()` for calls and `[]` for arrays/index with a **GPU retag pass** that uses only “previous token ends a Primary?” to split the punctuation into distinct terminals. With that, the grammar is cleanly **LLP(1,1)** and fits the same parallel model as our lexer and the ParallelLL parser.
