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
- bsnwav_TEXT: 3404 / 2016; subcode_TEXT: 6777 / 3946.
- MONIKERRESOURCE: 1104 / 1104.

MP3Dec and MP3Wav both build with aihelp.py in EC and NC. The decoder's NC
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
(67), and movable shared PCMCode (2756), WAVCode (1058), MP3ReaderCode (806)
and the original decoder resources. Every segment remains below 64 KB.
Only geos and ansic are imported; no ui or mp3dec import is introduced.

## MP3Wav migration

MP3Wav imports bsnwav protocol 1.8 and uses only the public bsnaudio.h
pull reader. Its input/feed state is removed. Each queued step reads PCM,
writes complete frames with the existing WAV writer, updates progress from
the borrowed source's file position and force-queues continuation. The
existing generation check, cancel/close cleanup, exclusive output creation
and removal of incomplete files are retained. Strict conversion rejects the
reader's damaged flag as well as fatal/truncated input or format changes.
The application's single output buffer is now 2048 bytes instead of 4608.

The writer now accepts BSNPcmFormat and validates signed 16-bit PCM frame
alignment and average rate; it still supports all nine MP3 native rates,
including decoder-only 48 kHz conversion. Both application builds pass.
Host converter output is byte-exact against the original core for all eight
sample files, and the existing writer format/overflow/I/O failure regressions
pass. The full original host corpus continues to pass.

Cancellation is serviced between synchronous reader calls; Open and ReadPCM
may perform input/metadata I/O and decoding before returning. GEOS UI timing
and cancellation responsiveness still require manual testing.

## Playback integration and compatibility

The actual Open -> BSNPcmPlay -> Close paths run under host GEOS/DMA shims
for all eight MP3 samples and 8/16-bit mono/stereo WAV. The check compiles the
production prepare/cache/conversion/playback/controller routines with the
real readers and decoder. Simulated DMA output matches original-core PCM
byte-for-byte, and known/unknown-length tails drain before cleanup. This is
not an audible GEOS runtime test. A 48-kHz source is rejected before starting
the simulated driver. Target ABI checks assert the packed source/format
layouts and four-byte callback pointer.

Reproduce the basic checks with Tests/check.pl. Passing the pinned upstream
checkout as its first argument additionally exercises public playback. An
optional second argument names a directory containing original-core raw PCM
files named after each input with .pcm appended, for DMA-output comparison.
Reference outputs and the exact invocation are retained under
~/pcgeos-tools/bsnaudio/phase8-reference and phase8-integration.log.

QuickPlayer (Appl/Audio/Bsqp) and Library/Wav compile and link EC/NC against
bsnwav 1.7 requirements, while the new MP3Wav requires 1.8. Their source and
DMA drivers are unchanged. Driver/Sound/BSD16/bsrecord.asm advertises a
44100-Hz maximum through BSDRecGetMaxProperties; BSD8ST advertises 22050 Hz.
BSNWPrepKS retains the 5001..44199-Hz source setup range. No 48-kHz playback
or speculative resampler/buffer enlargement is introduced.

QuickPlayer still creates its playback thread with a 3000-byte stack
(Appl/Audio/Bsqp/Main/subcode.goc). No claim is made that this is sufficient
for MP3: stack depth, worst decoder-call duration, active-resource paging,
underruns and audible output require manual GEOS measurements. No decoder
runs in an interrupt handler and no extra decoding thread is introduced.

## Application playback examples

Both entry paths use the same blocking engine and borrowed file ownership.
Check the Open result before playing, and always Close after a successful Open:

    BSNWav wav;
    if (BSNWavOpen(&wav, fh) == BSNW_STATUS_OK) {
        result = BSNPcmPlay(&wav.source, 0, 0);
        BSNWavClose(&wav);
    }

    BSNMP3Dec mp3;
    if (BSNMP3DecOpen(&mp3, fh) == BSNW_STATUS_OK) {
        result = BSNPcmPlay(&mp3.source, 0, 0);
        BSNMP3DecClose(&mp3);
    }

Applications doing conversion call ReadPCM directly instead of BSNPcmPlay;
they never supply compressed input to the decoder.

## Final validation and measurements

All 16 legacy exports retain their exact ordinal positions; seven new exports
are appended. The linked geode reports protocol 1.8, permanent name bsnwav,
token BSNW/16427 and 23 exports. Its only imports are geos and ansic. The
complete imported core and optimized assembly are byte-identical to the
pinned donor (the assembly filename differs). No other pre-existing branch
reference moved, including master.

Final linker resource sizes in bytes (EC / NC):

- dgroup: 10432 / 10432, writable fixed data.
- MP3MathCode: 67 / 67, fixed shared read-only code.
- ASMTOOLS_TEXT: 380 / 380, movable shared read-only code.
- AudioMainCode: 5607 / 3359.
- PCMCode: 4542 / 2756; WAVCode: 1690 / 1058.
- MP3ApiCode: 4366 / 2612; MP3ReaderCode: 1268 / 806.
- MP3DspCode: 10970 / 10970; MP3FrameCode: 21412 / 10796.
- MP3HuffCode: 16687 / 5359; MP3ImdctCode: 436 / 237.
- MP3QuantCode: 6068 / 2775; MP3SterCode: 10916 / 7342.
- MP3SynthCode: 1559 / 1238.

Except dgroup and MP3MathCode, every listed code resource is movable, shared,
read-only, discardable and swappable in the actual .geo. The linker reports
96400 / 60187 total resource bytes and 10499 fixed initialized/code bytes,
plus 132 bytes of uninitialized data/stack. Geodump records 120 additional
uninitialized bytes after the rounded initialized dgroup resource. Heap
rounding, resource/handle metadata, resident driver resources and live loaded
code are not runtime measurements here. The approximately 10-KB fixed decoder
table/data contribution is present even for WAV-only playback; moving those
tables requires locked-handle access and is deliberately deferred.

The resource audit found a pre-existing bridge-state error: Driver's udata
was not grouped with C dgroup and became a four-byte read-only code resource.
Including the native resource.def now puts driverInfo in writable dgroup;
all driver request/DMA instructions remain unchanged. The unused 1104-byte
moniker resource and its source asset are removed. Orphan parser/converter
comments and obsolete declarations are deleted.

Final PCM regressions additionally cover failed cache/DMA allocation followed
by retry with stereo toggling enabled. No toggle sample is written through
a null buffer. DMA accounting excludes the initial toggle sample and final
silence, so the last PCM sample is drained. The refill loop waits for space
for a complete source frame, including the partial cache space caused by
channel toggling. Unknown-stream accounting returns a source error before
4-GiB wrap; longer playback needs wider counters. A 65535-byte WAV read
request is capped at 65534 so a valid read cannot equal the error sentinel.
The host tests exercise that boundary with a 64-KB data chunk.

Source-based dynamic block/handle ownership, excluding all geode/resource,
thread and driver-loader handles:

- WAV reader alone: no owned memory handle; borrowed file remains open.
- MP3 reader alone: three movable blocks, unchanged from the original decoder:
  21730-byte target context, 2048-byte input, 4608-byte pending PCM.
- Common playback: one movable PCM cache, normally 8192 bytes.
- Existing BSD16/BSD8ST driver playback: one fixed DMA buffer plus one fixed
  1000-byte ISR stack (BSDRecAllocateBuffer and BSCreateStack).
- Thus source ownership predicts three playback blocks for WAV and six for
  MP3, in addition to library/driver resources. Actual GEOS live/peak handle
  counts, leaks and physical residency have not been measured.
- MP3Wav owns the three decoder blocks and one 2048-byte output block, plus
  its two file handles, application resources and process thread stack.

Final results:

- Audio library, MP3Wav, QuickPlayer and legacy Wav: EC and NC build/link pass.
- Original host corpus, trusted PCM accuracy, streaming, malformed-input,
  relocation, allocation/reset, new pull checks and real WAV conversion: pass.
- Standalone Watcom DOS: 32 inputs with EC/NC settings and actual linked ESP
  bytes are byte-exact; DSP, live-CS dispatch, 6486 products and public source
  layout/far-pointer assertions pass.
- Public playback host integration: all eight MP3 inputs, with/without the
  initial channel-toggle sample, match original-core PCM. All four native
  WAV sample layouts match; the 48-kHz source is rejected before driver start.
- Optional ASan/UBSan could not link: this environment lacks the referenced
  libasan.so.8.0.0 and libubsan.so.1.0.0. Normal host checks were rerun and pass.

Retained evidence is under ~/pcgeos-tools/bsnaudio/: final-build.log,
final-geodump-ec.txt, final-geodump-nc.txt, final-host.log, final-watcom.log,
final-integration.log, final-mp3wav.log, final-quickplayer.log and
final-legacy-wav.log. swat.rc sends bsnwav, mp3wav, bsqp and wav and ends in c;
no GEOS session or audible playback was started.

Remaining runtime work is explicit: audible WAV/MP3 output, Stop/Pause/Resume,
repeated playback under GEOS memory pressure, code reloads, driver-specific
conversions, allocation failures in the actual sound driver, worst decoder
latency/underruns, peak 3000-byte QuickPlayer stack use, and live handle/leak
counts. The host DMA shim does not replace those measurements. Midstream
format changes, 48-kHz playback, more than 64 recovery steps per reader call,
and playback sessions at or above 4 GiB of PCM are intentionally unsupported.
