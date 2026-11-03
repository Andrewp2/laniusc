# PostFrontEndWords

- GenP has the posts below build_files; front_end_words's own post (and front_end_files',
  front_end_read's) are not generated yet: add the root to pre_certs.py's post roots.
- leafA 11-03: proved by hand (Proof.lean), no generator change: an M-form post for the reader and
  validator cannot be generated (token starts are numbers, hb 0 in the inputs), so validate_files gets
  a post at a token bound T instead (attach conses one child per unit of cost; a `>>`'s second half is
  paid for by its `[62]`), T = the words' length (readFiles_ok), then post_build_files.
- Pitfall: after `simp only [Cost_...]`, omega may treat sums as atoms (non-standard `+` instance);
  restate the hypothesis/goal with `have h' : A + B < 2 ^ 64 := h` / `show`.
