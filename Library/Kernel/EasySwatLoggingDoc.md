## Documentation
1. **`TechDocs/Markdown/Routines/rroute_f.md`**
   - Document `EC_LOG_T(type, expr)` and `EC_LOG_STR(expr)` alongside other EC macros.
   - Note:
     - Tags are truncated to 31 bytes.
     - `EC_LOG_STR` interprets the pointer as a **far C string**.
     - `EC_LOG_T` requires `type` to be a symbol Swat can resolve (e.g., `word`, `WWFixed`, or a typedef/struct in symbols).

2. **`TechDocs/Markdown/Tools/tswatcm.md`**
   - Note that `why-warning` recognizes `EC_LOG_WARNING` and:
     - Prints strings when the tag is `"string"`.
     - Otherwise pretty-prints the value at `seg:off` using the tag as a type name.
   - Show example outputs and the `seg:off` display convention.

3. **Kernel dev docs (optional but recommended)**
   - Brief note in the EC/ERROR_CHECK section referencing these symbols and the `seg:off` encoding of `ECLogAddr`.
