Here’s a focused, implementation-grade summary of the paper’s ("ParallelLexingParsingSemanticAnalysis.pdf") lexer, distilled to just what you need to build it.

# What the paper proposes (at a glance)

* Compile the entire lexical grammar into **one deterministic finite automaton (DFA)** that can emit tokens *while it runs once left-to-right* over the input (a “streaming” DFA). This avoids chunking problems (e.g., strings/comments needing unbounded look-back) that break naive parallelization.&#x20;
* Evaluate that DFA **in parallel** by mapping each input symbol to a **unary transition function** (partial application of δ), then computing all prefix compositions with a **parallel prefix scan**. From those prefix results you can (a) know where tokens end and (b) read off their types. All heavy work becomes table lookups + a scan.

This design fixes the “am I inside a string or comment?” boundary problem that naive “split the text into chunks and lex each chunk” cannot solve.&#x20;

---

# Offline (host-side) preparation

Do this once per lexical grammar; then ship compact tables to the GPU.

1. **Build one streaming DFA from your regex grammar**

* Convert each token regex to an NFA (Thompson), graft all NFAs under a fresh start via ε-edges, then subset-construct to a DFA. If multiple NFAs accept at the same time, break ties by a fixed **priority rule** (e.g., order in your grammar).
* Turn the one-token DFA into a **single-pass, token-emitting DFA**: for every accepting state, **copy the start state’s outgoing transitions onto it** and mark those copied transitions as “emit a token of this state’s type”. If a copied edge conflicts with an existing edge from that accept state, **keep the existing edge** so you “prefer to continue the current match” rather than end early. Include a **reject state** that self-loops on all symbols; its final token map is ε (no token).

2. **Enumerate unary transition functions and their closure**

* For each input symbol **a**, form the unary function δₐ: Q → (Q, emitFlag). You will **not** store these as full |Q|-sized vectors per character at runtime; instead you will assign each distinct δₐ an integer id, and **precompute the closure of compositions** so combining two unary functions is a single table lookup. This avoids O(|Q|) work per composition during the scan.

3. **Build the three tables you’ll ship to the GPU**

* **Char → FuncId table.** For each alphabet symbol (e.g., 256 ASCII), store the id of its unary function (often encoded in 16 bits: 15 bits of id + 1 **emit** bit reserved for the last transition’s emit flag; paper uses this concrete packing).
* **Merge (composition) table.** A dense **m×m** table where entry (i,j) is the id of the composed unary function δⱼ∘δᵢ (function on the right applied last; consistent with your scan operator). Add a dedicated **identity element** (id 0) that composes as identity; this is convenient for exclusive/inclusive scans. Table entries are the same 16-bit encoded ids (so their top bit still carries the “emit” flag semantics used later).
* **FuncId → token/type table.** For each function id j, precompute the DFA state reached from the start, **δⱼ(q₀)**, and the associated token type **F(δⱼ(q₀))** (ε if “no token”). This is typically stored compactly (e.g., an 8-bit token id with a sentinel for ε).

**Notes/implications.**

* The “emit” bit belongs to the **transition** that just happened. In the streaming DFA, an emitting edge says “a token just completed before consuming this new char,” and its **type** is determined by the **source** state’s token mapping. During prefix processing we’ll therefore look **one prefix earlier** to read the token type.
* Memory: the merge (composition) table dominates space: O(m²). For realistic grammars, m (the count of distinct reachable unary functions and their compositions) is in the low thousands, but can grow with tricky features (e.g., strings + comments). The thesis reports tens of MB for a JSON lexer and discusses ways to shrink this (two-stage lexers; sparse/compressed tables; fitting in shared memory).

---

# On-GPU lexing (single pass over N characters)

Let the input be bytes b₁..bₙ.

1. **Map each char to a function id**
   For each position i, look up **fᵢ = CharToFunc\[bᵢ]**. This is embarrassingly parallel. (These ids carry the “emit” bit for the **edge at i**.)

2. **Parallel prefix-scan of compositions**
   Compute the prefix sequence **Fᵢ = fᵢ ∘ fᵢ₋₁ ∘ … ∘ f₁** using an **associative** binary operator defined by the **Merge** table; this is a standard scan (O(log n) depth). Use **exclusive** or **inclusive** consistently; if inclusive, define Fᵢ exactly as above; if exclusive, shift indices accordingly and keep an identity at position 0. The result at every i is the id of the composed unary function for the prefix 1..i.

3. **Find token boundaries (emits) and token types**

* **Boundary detection:** A token ends **at i** iff the composed function for prefix i indicates that the **last transition was an emitting edge**. Concretely, test the **emit bit** in **Fᵢ** (using the same bit packing you used in the tables). This gives you a boolean stream End\[i].
* **Token type at a boundary:** Type is determined by the **source state** of that emitting edge, i.e., by the state after processing the prefix **up to i−1**. So look up **TokType\[i] = TokenOf\[ Fᵢ₋₁ ]** (for i>1). For i=1, use the identity prefix (id 0). The **very last position n** must produce a token *even if the last transition’s emit flag is not set*; if **TokenOf\[Fₙ] = ε**, that’s a lexing error (“input does not end in a valid token”).

4. **Turn boundaries into slices (lexemes)**

* Compact indices where End\[i] is true into an array **ends\[k]** via parallel stream compaction. The matching starts are **starts\[k] = (k==0 ? 1 : ends\[k−1]+1)** (1-based positions; adjust for 0-based). Lengths are **len\[k] = ends\[k] − starts\[k] + 1**. You already have **type\[k] = TokType\[ ends\[k] ]** from step 3. (If you prefer, keep byte offsets and don’t extract substrings until later.)
* Optional: **filter** (e.g., remove whitespace/comments) here by masking specific token types and re-compacting. The paper’s lexing stage discusses the option of filtering at lex time; in any case the DFA should include those tokens so boundaries remain unambiguous.

That’s the entire GPU pass: **(map → scan → classify → compact)**. The only nontrivial kernel is the prefix scan over the merge table.

---

# Why this is correct (key rules you must preserve)

* **Longest match + priority** come from the DFA construction: subset-construction disambiguates multiple accepting regexes by a fixed priority scheme (put “keywords before identifiers,” etc.).
* **Streaming emission**: copying start-state edges onto accepting states and marking them “emit on the next char” ensures you emit *when you know the token can’t be extended*. Keeping an existing edge instead of the copied one ensures **continuation beats emission** (so you don’t prematurely end a longer token).
* **Type from the prior prefix**: because emission belongs to the transition you just took, the token’s type is read from the **state before that transition** (hence Fᵢ₋₁). The paper highlights this off-by-one rule explicitly.
* **Final token & errors**: the final prefix must resolve to a non-ε token; otherwise reject. A reject state with F=ε catches “fell off the DFA” cases.

---

# Complexity & memory characteristics

* **Work**: All operations are table lookups plus a single parallel scan. Depth is **O(log n)**; total work is O(n). Classic Hillis-Steele style, but with a precomputed closure so the scan operator is **O(1)** (one 2D table lookup) rather than O(|Q|).
* **Space**: Dominated by the **m×m merge table** where m is the number of distinct reachable unary functions (including their compositions). The thesis reports \~**35 MB** for a JSON grammar; it proposes (for richer languages) a **two-stage lexer** (stage 1 classifies regions like “in string/comment/code”, stage 2 does proper tokens) and **sparse/compressed tables** so the merge table fits **shared memory** per SM, improving speed.

---

# Practical build sheet

**Inputs you need**

* Regexes for tokens (with priority order). Keep “comment/string” forms explicit; the method handles unbounded spans.

**Host-side generator**

1. Build NFA per regex → combine via ε → subset-construct DFA. Mark accept states with token types and define a **reject** state.
2. Convert DFA to **streaming** DFA (copy start edges to accepts; mark “emit”; keep conflicting existing edges).
3. Enumerate **unary functions** for alphabet symbols; assign ids; compute the **closure of compositions** reachable in real inputs (BFS over pairs with memoization) to fill **Merge**.
4. Emit three arrays:

   * **CharToFunc**: Σ → 16-bit id (top bit = per-edge emit; paper shows this exact layout).
   * **Merge**: m×m 16-bit ids; include **id 0** = identity.
   * **TokenOf**: m → 8-bit token id (ε sentinel).

**Device-side (per file)**

1. Map input bytes to **fᵢ** with CharToFunc.
2. Inclusive prefix-scan with **Merge** to get **Fᵢ**.
3. Boundaries = high-bit(Fᵢ). Types = **TokenOf(Fᵢ₋₁)** with i-1 identity at start; ensure final i=n emits or else **TokenOf(Fₙ) ≠ ε**.
4. Compact to (type, start, length); optionally filter (whitespace/comments).

That’s enough to code the lexer without the rest of the thesis. If you want to push performance and memory further, the paper’s future-work section suggests a two-pass lexing pipeline and compressing the merge table to fit shared memory (big gains on GPUs).

---

## Citations (relevant excerpts)

* Why naive parallel chunking fails; strings/comments need unbounded look-back; overall two-phase design of an offline DFA + on-GPU pass.&#x20;
* DFA construction and streaming transformation; emission timing and “continue vs end” choice.&#x20;
* Parallel evaluation via prefix compositions; off-by-one rule for token types; last-token validity check.
* Table layouts and identity element; composition implemented as a 2D lookup; bit-packing used in the implementation.&#x20;
* Memory/merge-table size, two-stage lexing, and shared-memory motivation.
