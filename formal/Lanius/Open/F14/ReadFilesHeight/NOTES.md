# ReadFilesHeight

- SelfPre/Files.lean: readCountedFiles_ok (filesSize at most W.length, tokens' starts and texts bounded).
- leafA 11-03: proved (Proof.lean). readFiles_ok misses the files' count; readFile_ok's strict `<`
  gives files.length + filesSize ≤ words (readFiles_count); hb fs ≤ length + filesSize + B.
