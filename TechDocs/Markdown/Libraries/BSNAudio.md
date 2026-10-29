# Unified BSNAudio implementation

## Baseline (2026-10-29)

Implementation branch BSNAudio-unified starts at PCM-source-v2 commit
1d4ea7818cb95294145e65410d462d4fe27ccc90. The decoder import is pinned to
micromp3 commit c230523694bf8d84f86fa86c911974305b99ec28. Neither source
branch nor master is modified.

The PCM baseline fails EC and NC linking: BSNWPlay calls the undefined
BSNWStartPlay. The prerequisite fix calls the already declared and implemented
BSNWAsmStartPlay in ASMTOOLS/asmtoolsManager.asm. No driver or DMA changes.
After this fix aihelp.py build Library/Audio/BSNAudio succeeds in EC and NC.
Existing warnings concern unused variables/parameters and unprototyped
ProcCallFixedOrMovable_pascal calls.

Baseline linker resource sizes (bytes, EC then NC):

- dgroup: 272 / 272, fixed; uninitialized data/stack: 152 / 152.
- udata: 4 / 4; ASMTOOLS_TEXT: 380 / 380.
- bsnwav_TEXT: 3404 / 2016; subcode_TEXT: 6780 / 3946.
- MONIKERRESOURCE: 1104 / 1104.

MP3Dec and MP3Wav both build with aihelp.py in EC and NC. The decoder's
linked resources contain fixed dgroup (10176 bytes) and MP3MathCode (67),
and movable shared code for MP3DspCode (10970), MP3FrameCode (10796),
MP3HuffCode (5359), MP3ImdctCode (237), MP3SynthCode (1238),
MP3QuantCode (2775), MP3SterCode (7342), and mp3api_TEXT (2601).
The existing decoder allocates three movable blocks per instance (context,
2048-byte compressed input, 4608-byte PCM); actual GEOS live handle counts
have not been measured.

The pinned upstream micro-mp3 checkout is
07c18fa2d045b89bcc19aa0c1dc5333ce69b39db. Existing host checks pass all
eight upstream inputs, including six feed sizes, byte-exact reference core
and WAV conversion, relocation, allocation failure, reset and malformed input.
Standalone Watcom DOS checks pass all eight inputs with EC/NC flags and the
actual linked ESP DSP resources, plus DSP regression, live-CS Huffman dispatch
and 6486 fixed-point products. This does not run PC/GEOS.

Reproduction and retained logs are under ~/pcgeos-tools/bsnaudio/. Tests use
TMPDIR=~/pcgeos-tools/bsnaudio/tmp and KEEP_TESTS=1. The baseline snapshot is
an archive of only the decoder, converter and headers, not a branch merge.

mkmf discovers source modules in Library/Audio/BSNAudio and generates the
Installed module Makefile; aihelp.py builds in Installed. pmake lib publishes
the library definition to Installed/Include. The hand-maintained top-level
Installed/Makefile has the bsnwav target and Wav, MixLib, Bsqp and SndChk
consumer dependencies. Subdirectory Makefiles and dependencies are generated.

## Common source contract

CInclude/bsnaudio.h defines format-independent BSNPcmFormat and BSNPcmSource.
The far Pascal reader returns complete PCM frames, zero at EOF and 0xffff
on error. Short positive reads are valid. The descriptor and opaque context
remain valid and locked throughout blocking playback; decoder-owned movable
state is referenced through handles inside that context. Callback pointers
are GEOS virtual code pointers and require ProcCallFixedOrMovable_pascal
with callback arguments first and the code pointer last.

BSNPcmPlay is appended after the existing exports with incminor. The geode
remains bsnwav.lib and retains its token. The PCM module now consumes that format and calls only the reader callback;
legacy file/callback entry points adapt their inputs outside PCM. Callback
invocation uses a typed Pascal trampoline with the code pointer last.

Run the PCM regression with:

    TMPDIR=~/pcgeos-tools/bsnaudio/tmp perl Library/Audio/BSNAudio/Tests/check.pl

It compiles the actual cache, conversion and playback loop routines against
a synchronous DMA/GEOS host shim. Checks cover short reads, known/unknown
lengths, early EOF, buffered tail draining, source errors after playback starts,
invalid byte counts/frame alignment, and rate-reduction chunk independence.
The existing conversion and DMA implementations are retained; cache filling
now combines short reads before conversion, the cache boundary aligns with
reduction groups, and final reduction skips cannot underflow cacheFull.
An error from a refill is preserved instead of being overwritten by drain
accounting. EC and NC builds pass after this extraction.

The full pinned minimp3 corpus also passes the original decoder checks:
32 inputs through actual EC/NC ESP resources and all host core/streaming
comparisons, including the trusted PCM accuracy gates.

## Unverified runtime behavior

PC/GEOS was not started, as required by AGENTS.md. Audible playback, DMA
underruns, movable resource reloads, live handle counts and peak playback
stack use require later manual testing. Compilation and standalone DOS
checks do not establish those results.

## WAV reader

BSNWavOpen, BSNWavReadPCM and BSNWavClose operate on a caller-owned BSNWav
context without allocating handles or requiring playback. Open validates the
RIFF extent, chunk sizes/padding and PCM format, supports data before fmt,
and selects the first data chunk. Reads return only complete frames within
that chunk; a truncated read is an error. Close leaves the borrowed file open.
The reader accepts native PCM rates independently of hardware. Playback
explicitly rejects rates outside the existing 5001..44199 Hz setup range,
including 48 kHz, rather than playing at an incorrect rate.

BSNWavePlayFile adapts the reader to the common PCM engine. TEST_ONLY and
GetLastFormat retain format/length reporting, PLAY_POS seeks within the data
region with bounded arithmetic, and playback uses the existing single-active
session. Invalid container headers retain the legacy memory-error result;
unsupported PCM returns unknown-format. The separate Library/Wav is unchanged.
The host regression additionally compiles the actual WAV reader and checks
8/16-bit mono/stereo, empty/short data, odd chunk padding, chunk order,
every file truncation, malformed sizes/formats, read failures and borrowed
file ownership. EC and NC builds pass.

## Decoder transplant

MP3Dec is compiled directly into bsnwav.lib, with no mp3dec library import.
The pinned implementation, core, Apache LICENSE/NOTICE and regression suite
are preserved. Only private-header lookup, API code-resource placement and
test paths change; mkmf requires mp3dsp.asm to be named mp3decManager.asm in
its source module. The instruction bytes are unchanged. dgroup is fixed and
writable because it also contains mutable playback globals; the immutable
MP3 tables remain directly addressable. The 386 kernel-register requirement
is retained explicitly; no kernel configuration is changed.

The original MP3Wav sources are imported to retain conversion regressions;
their GEOS client migration to the combined pull interface follows separately.
The decoder's feed API/header is private to MP3Dec and is not exported by the
combined library. EC and NC combined-library builds pass.

## Pull-based MP3 reader

BSNMP3DecOpen, BSNMP3DecReadPCM and BSNMP3DecClose expose the same source
contract as WAV. Open probes with zero output capacity, retaining the first
PCM frame inside the existing decoder block. Read drains pending PCM and
performs file I/O only on NEED_INPUT. It reads directly into the decoder's
locked compressed-input block, bounded by its free capacity: all read bytes
are accepted, and no unaccepted suffix or additional buffer is possible.
The reader still owns only the decoder's original three handles. Close
releases these blocks and leaves the borrowed file open.

PCM accompanying RECOVERABLE is returned; other recoveries continue with an
explicit 64-recovery-per-call limit. Long damaged regions beyond that ceiling
need an incremental recovery API. The context's damaged flag lets strict
converters reject concealment/recovery while ordinary playback can proceed.
Fatal/truncated input and file errors return the PCM error sentinel and latch
status. Midstream format changes latch unknown-format and are rejected before
returning new-format PCM. EOF follows pending PCM drainage.

The pull checks compare all eight upstream files byte-for-byte with the
original core for compressed read chunks of 1, 3, 7, 127 and 2048 bytes and
511-byte PCM capacities. They also verify retained probing output, tiny output
capacity, interleaved instances, relocation on every unlock, all three initial
allocation failures, borrowed files, repeated close, file-read failures,
truncated final frames and format-change rejection. Both GEOS builds pass.

## Final source and resource organization

Library/Audio/BSNAudio contains Main (library/legacy adapters), PCM, WAV,
MP3Dec and Driver. The permanent name and library definition remain bsnwav.
The top-level Installed/Makefile is a hand-maintained product graph; its
bsnwav target now points at BSNAudio. Module Makefiles/dependencies are
regenerated with mkmf and pmake depend.

mkmf derives GEODE from the directory name, so local.mk explicitly overrides
it to bsnwav and reads the matching revision before linking. The historical
Bsnwav.rev capitalization also prevented Unix revision discovery; it is now
bsnwav.rev. This restores base protocol 1.6 (the original GP export tranche
adds one minor, the new appended tranche adds another). Existing export
positions are retained. The accidentally generated 0.x baseline protocol is
not used for the final library.

The compiled-out reference multiplier remains in the source and host/DOS
checks but is excluded from GEOS objects. Its empty Watcom CodeView type
stream triggers an existing glue parser error with the new module order.
The assembly math helper is still linked. The private legacy callback adapter
uses a global internal symbol because this glue cannot resolve a static
callback address when its merged resource's first contributor is another
object; no extra GP export is added.

The linked NC map confirms writable fixed dgroup (10432 bytes), fixed math
(67), and movable shared PCMCode (2572), WAVCode (1037), MP3ReaderCode (806)
and the original decoder resources. Every segment remains below 64 KB.
Only geos and ansic are imported; no ui or mp3dec import is introduced.
