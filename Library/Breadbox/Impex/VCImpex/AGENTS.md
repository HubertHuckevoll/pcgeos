This monorepo is for creating code for the 16-bit PC/GEOS operating environment for DOS from the late 80s, early 90, also known as
GeoWorks Ensemble, Breadbox Ensemble, NewDeal Office.

The layout of the repo is:
Appl/ – sample + system apps (GeoWrite/GeoDraw-style code lives around here)
Library/ – GEOS libraries (UI, graphics, VM/DB, etc.)
Driver/ – DOS/video/mouse/printer drivers
Include/ - headers for ESP, the PC/GEOS object oriented assembler and link defs
CInclude/ – headers for GOC/C and link defs
Tools/ – source of build/debug tools (pmake, swat pieces, build scripts)
Loader/ – boot/loader bits
TechDocs/ – the SDK docs (use TechDocs/Markdown first, as it contains the latest version of the docs)
Installed/ - this folder contains "Appl", "Library" and "Driver" again. Code is being built here.
bin/ – where the tools land once they have been built.

Coding style rules:
- Always indent C-Code with 4 spaces, ASM (ESP) code with tabs according to the surrounding code.
- Put curly braces always on a new line when creating functions, for blocks inside a function put the opening `{` on the same line and the closing `}` on a new line.
- Handles and pointers are always distinguished and named clearly with a trailing H for Handles and a trailing P for Pointers.
- never use anything else but pure ASCII characters when creating code

GEOS Coding and Behavior Guidelines:
- Generate code in **GOC language**, which transpiles to **Watcom C 16-bit** using the `goc` tool.
- Generated code must follow the C89 standard: Variables must be declared at the **top of functions** (not blocks!), no new blocks are introduced solely for the purpose of introducing variables mid-function.
- Cast all void pointers like this: `(void*)0`.
- Declare functions as _pascal by default.
- Keep stacks small: no big local variables (use MemHandles or LMemHeaps instead), use early returns whenever possible.
- Use small buffers, usually not more than 8 kb, 32 kb at most.
- When creating librarys, don't use globals, but context structures that are passed to every function.
- Memory management must follow the `MemAlloc` (always use `HAF_ZERO_INIT` as the last parameter), `MemLock/MemUnlock`, and `MemFree` pattern, not "malloc" / "free".
- Use `WWFixed` math instead of `float` whenever applicable.
- Don't re-create aliases for the HIGHC compiler, even if you find them in the source code.
- Use typedef's for defining callback functions instead of the PCM macro also found in the source code, like this:
`
...
typedef Boolean _pascal ProgressCallback(word percent);
typedef Boolean _pascal pcfm_ProgressCallback(word percent, void *pf);
...
int _export _pascal ReadCGM(FileHandle srcFile,word settings, ProgressCallback *callback)
{
...
}
...
if(((pcfm_ProgressCallback *)ProcCallFixedOrMovable_pascal)(pct,callback))
{
...
}
`

By default, don't try to compile / test applications you've created.