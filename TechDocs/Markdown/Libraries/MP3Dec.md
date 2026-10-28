# MP3Dec and MP3Wav port report

## Status

MP3Dec is the reusable product. MP3Wav is a separate, disposable conversion
client. Both build as EC and NC GEOS geodes. The converter imports mp3dec.lib
and includes only the public mp3dec.h header. It embeds no decoder sources.
Neither the kernel nor the existing WAV library is changed. GEOS now uses a
386 integer ESP backend for multiplication, synthesis/DCT32, IMDCT/overlap and
alias butterflies; the C reference and public API remain available unchanged.

The branch started clean at master commit
690d15fc771ff237f0f1306e83ecc3a494bd4c6a. Decoder sources come from
https://github.com/esphome-libs/micro-mp3 at
07c18fa2d045b89bcc19aa0c1dc5333ce69b39db. Library/MP3Dec/LICENSE and NOTICE
preserve Apache 2.0 licensing and PacketVideo/microMP3 attribution.
core/CHANGES.md records upstream and port changes. The ESP32 C++ wrapper is absent.

The agent has not started PC/GEOS. The user's initial manual EC conversion
attempt stopped in FatalError with an invalid backtrace. A GEOS-only Huffman
trampoline argument-order bug was then found and corrected: Pascal requires
the callback pointer last. The initial target regression rejected the old
order and passed 1000 calls with balanced stack for the corrected order.
A subsequent manual run reached 43% before an RCI checksum failure.
Static analysis found both continuation sends lacked forceQueue: same-thread
ObjMessage dispatch was recursively entering the next step instead of queuing
it. Both sends now force the event queue, and the generated EC code passes
MF_FORCE_QUEUE (0x4000) at both sites. The 4096-byte stack is unchanged.
The user subsequently confirmed successful GEOS conversion and measured about
156 seconds for the 205-second music sample. That measurement precedes the
progress/dispatch optimization below; its GEOS speedup remains unmeasured.
The evidence below distinguishes host tests, standalone Watcom DOS tests,
GEOS linking and user-reported manual runs.

## Public API and binary interface

CInclude/mp3dec.h is the entire public interface. The six ordered exports are
Mp3DecCreate, Mp3DecFeed, Mp3DecReadPCM, Mp3DecGetFormat, Mp3DecReset and
Mp3DecDestroy. Protocol 1.0 fixes their order and the format structure layout.
Future compatible exports must be appended with the usual GP minor protocol
change; existing exports must not be reordered.

Calls use far Pascal stack arguments, declared _pascal _export. Results are
16-bit words; the opaque instance is a MemHandle. Mp3DecFormat is a 32-bit
sample rate followed by a 16-bit channel count, six bytes with target packing.
There are no public OpenCORE pointers or structures.

Create returns an owned instance through its output argument. Feed copies
compressed bytes and always reports the exact accepted count. INPUT_FULL
requires draining output and retrying only the unaccepted suffix. FEED_END is
latched only if every supplied byte was accepted. It can be supplied on an
empty feed. Further input requires Reset.

ReadPCM decodes at most one MPEG frame, or drains already decoded PCM. The
output is signed 16-bit native-rate PCM, mono or interleaved left/right stereo.
Its count is PCM frames, meaning one sample per channel. Byte capacity need
not hold a complete MPEG frame. Complete PCM frames are returned and the rest
remain pending. A future ring buffer can stop calling ReadPCM for any duration;
Feed eventually returns INPUT_FULL and nothing is discarded.

Result values are PCM/success (0), NEED_INPUT (1), OUTPUT_SMALL (2),
FORMAT_CHANGED (3), END (4), RECOVERABLE (5), FATAL (6), BAD_ARGUMENT (7),
NO_MEMORY (8), INPUT_FULL (9) and TRUNCATED (10). Create, Feed and Reset use
zero for success. FORMAT_CHANGED publishes the new format with zero output;
new-format PCM remains pending for the next read. RECOVERABLE can accompany
concealment PCM; frames and format remain valid. The converter deliberately
fails and removes output on decoding errors or format changes.

NEED_INPUT differs from terminal TRUNCATED after FEED_END. An empty stream
ends without PCM. Initial ID3v2, ID3v1 trailers and header-bearing APEv1/v2 tags
are skipped with bounded storage. APE declarations are capped at 16 MiB.
Headerless APE item data and arbitrary trailing junk can produce a recovery
error. Free-format and Layers I/II are unsupported. There is no gapless
encoder-delay/padding trimming, resampling, sound output or scheduling in the
library. Xing/Info frames are decoded as frames, matching the raw core oracle.

## Memory ownership and relocation

One instance owns three HF_SWAPABLE, zero-initialized GEOS blocks:

- Decoder context: 21730 bytes, including the 21652-byte contiguous core and
  50-byte external core interface.
- Compressed input: 2048 bytes.
- Pending PCM: 4608 bytes, the largest MPEG-1 stereo frame.

The per-instance persistent allocation is 28386 bytes plus GEOS handle/heap
overhead. Immutable tables/strings additionally occupy one 10176-byte fixed,
read-only shared DGroup per loaded library, not per decoder. Cross-resource
compiler data references require a real segment: -zc would put these tables in
movable code and produce invalid direct data references. Keep the fixed data
segment until table access is changed to lock and rebind handles explicitly.
The core's contiguous block is the documented exception to the usual 8 KB
buffer preference. Splitting its two channel structures requires changing
core accesses; it is below 32 KB and below a segment. No large scratch arrays
are on the decoder stack. Scratch storage belongs to each core instance.

Callers own input and output buffers and keep them valid and locked for each
call. Each buffer must fit in one segment. No caller pointer is retained.
Calls on one instance must be serialized; independent instances may be
interleaved. No mutable global decoder state exists.

Public calls lock the context only for their duration. Decode locks input and
PCM blocks while using them. mainDataStream.pBuffer is rebound to the relocked
reservoir on every decode. Both internal bitstream pointers and both external
buffer pointers are cleared before unlocking. Huffman procedure pointers are
GEOS virtual code pointers. The internal call path combines their stable
offsets with the current CS only while MP3HuffCode is executing and locked.
The real address is never stored back in the context, so relocation/reload
between public calls remains safe. All Huffman callbacks and their callers
must remain together in MP3HuffCode; cross-resource callbacks require the
GEOS trampoline again. These are code pointers, not pointers into movable data.
Destroy releases all three blocks; Reset reuses them and clears all history.

The host heap shim relocates every unlocked allocation. Its checks cover
allocation failure at each of the three allocations, end-of-stream latching,
input capacity, tiny output buffers, reset equivalence and two interleaved
instances. Host malloc/free occur only in test infrastructure.

## Reference C and assembly boundaries

The core is C89, compiled in Watcom's large model with Pascal internal calls
and SS different from DS. int32/uint32 map to signed/unsigned long on target.
The target checks verify int=2, int32=4 and data/function pointers=4 bytes.
Compile-time floating Q operands are frozen to original host-reference integer
values. The decoder requires no floating-point or 64-bit runtime operations.

Mp3MulShift takes two signed 32-bit values and a 16-bit shift. Its C reference
uses unsigned partial products to reproduce a signed 64-bit product without a
64-bit runtime. The ESP target uses one signed IMUL for the full EDX:EAX product
and SHRD after explicit rounding.
Q27 through Q30 add half an LSB before shifting. Q32 truncates. Accumulation
wraps explicitly in unsigned arithmetic. Arithmetic right shifts and
signed left-shift/wrap idioms inherited from OpenCORE are verified against
target output; host tests use -fwrapv. The optional sanitizer configuration
excludes shift checks for those inherited idioms.

The reference multiplier is out of line on Watcom because inlining it made EC
DSP resources exceed 64 KB. No call was added around each ordinary add/shift.
A volatile temporary in pvmp3_mdct_18 prevents an observed -ox shift omission;
Tests/dsp.c preserves the regression. CRC/reservoir concealment status is
retained instead of being overwritten with success at the end of a frame.

The existing independent Pascal interfaces remain the replacement boundaries:

- Mp3MulShift: fixed ESP entry in mp3dsp.asm; C reference in mp3fxp.c.
- pvmp3_huffman_parsing and per-table procedures for Huffman decoding.
- pvmp3_imdct_synth, pvmp3_mdct_18 and pvmp3_mdct_6 for IMDCT/overlap.
- pvmp3_poly_phase_synthesis and pvmp3_polyphase_filter_window for synthesis.
- pvmp3_dequantize_sample and pvmp3_alias_reduction for other DSP work.

Their private headers specify all arguments. int16 pointers address signed
samples; int32 pointers address fixed-width work arrays within locked blocks.
An ESP replacement must preserve the Pascal ABI, far pointer segments and
callee-saved registers, including DS, and must not assume DS=SS. Follow
Library/WebpLib/webpfilter.asm for shared code resources and C entry stubs.
GEOS selects MP3_386_DSP at the translation-unit boundaries. The default host
and standalone DOS builds retain the C implementation. The ESP backend requires
386 register preservation (SUPPORT_32BIT_DATA_REGS) and fails assembly for older
product configurations. It uses no FPU, MMX, SIMD or mutable global data.

mp3dsp.asm follows WebpLib's Pascal C/ESP entry pattern. MP3MathCode is a
67-byte fixed, shared, read-only helper returning DX:AX; it has no movable
resource call per product. MP3DspCode contains synthesis/windowing, DCT32,
long/short IMDCT, overlap/inversion and alias butterflies. Inner products use
local instructions/macros; the granule loops retain locked segments. The C
wrappers retain equalization/transposition and alias block-limit selection.
Windows and cosine constants live with the DSP code and use CS-relative access.
The assembled DSP resource is 11653 bytes with no GEOS loader relocations.
Private DCT16 scratch is 76 bytes; this is not a peak nested stack measurement.

The target/reference C equivalence gate is bit exact, including rounding,
clipping and overlap history. An assembly replacement must meet that same gate;
the up-to-two-LSB differences from trusted ISO PCM are properties of the reference
algorithm, not an extra assembly error allowance.

## Validation and reproduction

Run from the repository root with a checkout at the pinned upstream revision:

    perl Library/MP3Dec/Tests/check.pl /path/to/micro-mp3 /path/to/vectors
    perl Library/MP3Dec/Tests/watcom.pl /path/to/micro-mp3 /path/to/vectors
    MP3_ASM=1 KEEP_TESTS=1 perl Library/MP3Dec/Tests/watcom.pl /path/to/micro-mp3 /path/to/vectors

The vectors come from lieff/minimp3 commit
7b590fdcfa5a79c033e76eacc05d0c3e4c79f536, the same pin used by upstream
microMP3's conformance runner. Neither external checkout nor fetched vectors
are committed here. KEEP_TESTS=1 retains temporary evidence. Tests use Perl,
C, GCC/G++, Open Watcom and BaseBox; no test framework is required. The DOS
runner suppresses all user/local BaseBox configs and never boots PC/GEOS.
MP3_ASM=1 requires freshly built GEOS geodes. It wraps the actual linked ESP
resource bytes in a DOS object, preserving resource offsets and CS constants;
it does not reimplement or reassemble the DSP instructions with another assembler.
The retained nc.obj can also be profiled by setting MP3_ASM_OBJECT to its absolute
path when running Tests/profile.pl. Re-extract after any ESP change.

Observed results on 2026-10-28:

- The C89 core matches the original C++ core byte for byte on all eight upstream
  sample files and the selected upstream Layer III corpus.
- Six feed sizes (1, 3, 7, 127, 2048 and 65535) produce identical sample-corpus
  PCM. Interleaved instances use different sources and pacing. Reset checks
  compare complete PCM hashes and sizes, not just frame counts.
- Trusted-reference streams also pass streaming comparisons, including MPEG-1,
  MPEG-2, MPEG-2.5, mono/stereo, VBR, CRC and midstream format changes.
  All 23 direct trusted-PCM comparisons meet the upstream 96 dB / 2 LSB
  gate; the observed minimum is 99.17 dB and maximum difference is 2 LSB.
- WAV tests cover all nine native sample rates, mono/stereo, exact payload and
  final RIFF/data lengths, short writes, write/seek errors, format mismatch and
  RIFF size overflow. The real API plus writer produces byte-exact sample PCM.
  FFprobe recognizes the generated stereo WAV as pcm_s16le at 44100 Hz.
- The malformed-stream check completes 256 corrupted/truncated cases with
  bounded input/output calls. Corrupt vectors without trusted PCM are checked
  as raw-core equivalence/robustness, not accepted as valid converter input.
- Standalone DOS builds with EC and NC compiler options produce exact host PCM
  for 32 inputs: eight samples plus 24 corpus inputs. The DSP regression and
  6486 target fixed-point products also match, including signed extrema and
  rounding/carry edges. With MP3_ASM=1 the same 32 PCM comparisons pass through
  actual EC/NC ESP resource bytes. The focused DSP check allocates distinct
  DOS segments for input, history and short-block scratch. The live-CS Huffman
  path also passes these comparisons with MP3_HUFF_LOCAL enabled. Tests/thunk.c
  makes 1000 calls with a deliberately invalid virtual segment, checks the
  returned value and balanced stack, and verifies the virtual pointer stays
  unchanged. EC/NC disassembly shows MOV AX,CS and an ordinary indirect far
  call, with no ProcCallFixedOrMovable reference in mp3huff. The host multiplier
  additionally checks 1.2 million randomized products and signed edge cases.
- aihelp.py builds both actual GEOS geodes in EC and NC. Geodump confirms six
  library exports and the separate mp3dec import in MP3Wav. Code resources are
  read-only shared; the 67-byte multiplier is fixed and the DSP resource is movable.
  Remaining immutable C tables use a fixed read-only shared
  DGroup; the decoder library keeps no instance state there.

The optional SANITIZE=1 host run could not link: the installed GCC sanitizer
linker scripts refer to absent libasan.so.8.0.0 and libubsan.so.1.0.0 runtimes.
No sanitizer pass is claimed and no dependency was installed to work around it.

Build and publish the library before the converter:

    mkdir -p Installed/Library/MP3Dec Installed/Appl/MP3Wav
    (cd Installed/Library/MP3Dec && mkmf && pmake depend)
    ~/pcgeos-tools/aihelp.py build Library/MP3Dec
    (cd Installed/Library/MP3Dec && pmake lib)
    (cd Installed/Appl/MP3Wav && mkmf && pmake depend)
    ~/pcgeos-tools/aihelp.py build Appl/MP3Wav

The generated Makefile/dependencies.mk files are checked in, following repository
conventions. swat.rc contains send mp3dec and send mp3wav and ends with c.

## Performance investigation

Tests/profile.pl instruments a temporary copy and validates its PCM against the
reference before reporting timings. It does not change the shipped library.
Use CPU and CYCLES environment variables to repeat an emulator scenario.

The 79-frame 44100-Hz stereo sample contains 91008 PCM frames, about 2.064 seconds
including encoder delay/padding. In BaseBox's normal CPU core, the measured NC
frame-decode totals were 46.741 seconds at cputype=386, cpu_cycles=15000 and
23.343 seconds at cputype=486_slow, cpu_cycles=30000. Average frame-decode times
were about 592 ms and 295 ms respectively. These are emulator scenarios, not
calibrated MHz or hardware benchmark claims. Instrumentation has overhead.

In the 386 scenario, polyphase synthesis accounted for 31.583 seconds (about
68%), IMDCT 10.106 seconds (22%), alias reduction 2.198 seconds, dequantization
1.922 seconds and Huffman work 0.877 seconds. The 486 scenario was similar.
Small phases can fall below the DOS clock's resolution. Polyphase synthesis is
the measured first candidate for a whole-routine 386 assembly replacement.
The C reference is far from real-time at these settings.

After the ESP multiplier, synthesis and IMDCT replacements, the same 486_slow /
30000-cycle scenario took 1.978 seconds. Alias reduction then represented about
19% of decode time, so its butterfly loop was also moved to ESP. The final run
took 1.757 seconds for 79 frames, or about 22.2 ms per MPEG-1 frame: 13.3 times
faster than the 23.343-second C baseline. All benchmark PCM remained bit exact.
About 15% of the 26.1-ms decoder-only budget remains in this emulator scenario;
this does not establish real 486 speed or playback headroom under GEOS.

Before the local Huffman dispatch change, coarse phase totals were synthesis
605 ms, IMDCT 493 ms, Huffman 385 ms,
dequantization 165 ms and alias reduction below timer resolution. The DOS clock
advances coarsely, so phase totals are approximate and individual zeroes do not
mean free work. WAV output, UI, GEOS dispatch and audio playback are not timed.
The retained final evidence is /tmp/mp3wat-bbBQaZ (32 PCM comparisons and focused
checks) and /tmp/mp3prof-fFeJmv (profile). These temporary paths are not fixtures.

Disassembly shows the largest explicit local frame reservation is 310 bytes
in the original EC dequantizer and 126 bytes in the original NC C DCT16. This is not a peak-stack
measurement: nested arguments, GEOS dispatch and memory operations add usage.
The converter reserves a 4096-byte process stack. Actual EC peak stack,
heap/handle behavior, responsiveness and cancellation remain runtime checks.

## EC/Swat handoff

Start the target manually when authorized. With EC geodes sent by swat.rc,
run mp3wav, then set source breakpoints with the documented stop-at syntax:

    run mp3wav
    stop at /home/konstantinmeyer/pcgeos/Appl/MP3Wav/mp3wav.goc 196
    stop at /home/konstantinmeyer/pcgeos/Library/MP3Dec/mp3api.c 265
    ec all
    c

For the callback-crash investigation, swat.rc currently sends both geodes,
starts mp3wav and stops at mp3api.c line 230 before the first decode, plus
bootBoot.asm line 870 on entry to FatalError. EC markers
MP3DEC_DEBUG_CONTEXT_READY and MP3DEC_DEBUG_FIRST_FRAME distinguish successful
context construction from entry to frame decoding. At the first-frame stop,
use locals and bt -sp 40, then c to continue through the diagnostic warning.
These markers are EC-only and do not increase the process stack allocation.

The source breakpoint is near the conversion step. Use the current source line
of MSG_MP3WAV_STEP if later edits move it. At a breakpoint, use locals,
bt -sp 40 and ps -t mp3wav to inspect arguments, context and stack use. Continue
with c. Do not infer a loop from a single expensive synthesis call.

Select an MP3 and a new DOS 8.3 filename such as CONVERT.WAV. Confirm the output
starts with RIFF at host byte zero and compare its PCM after the 44-byte header
against the host raw-core output. Exercise mono/stereo and every MPEG version,
VBR, CRC, ID3 and APE metadata. Check existing output/source names are refused
without modification. Test full-disk/write errors, truncated frames and format
changes; incomplete output must be removed or an explicit cleanup error shown.

Cancel during input, decoding and WAV output; close during conversion; then
start another conversion. Verify no decoder/file handles remain, queued stale
continuations are ignored and the UI continues repainting. Check actual peak
stack under EC and repeated conversions under memory pressure. The local-CS
Huffman dispatch and real movable GEOS allocations particularly need this run;
DOS tests and the host relocation shim cannot establish their GEOS runtime behavior.

## Remaining performance handoff

Confirm the queued conversion fix and the new ESP path under GEOS. Time NC
decoding separately from EC diagnostics, WAV writes and UI updates. Measure on
real hardware, or calibrate the emulator before assigning a 486 clock speed.
For 44100-Hz MPEG-1, one 1152-sample frame has a 26.1-ms real-time budget; aim
below it with playback headroom.

MP3Wav now updates progress only when the displayed integer percentage changes;
the initial zero and successful final 100 remain explicit. Queued continuation
scheduling and cancellation are unchanged.

Huffman decoding now calls the selected table procedure directly within the
active MP3HuffCode resource, using its offset and the current CS. This removes
the per-codeword GEOS trampoline without fixing the whole resource in memory,
adding handles or changing the decoder's public API or context layout.
The 32-input EC/NC PCM comparison and 1000-call dispatch check pass after this
change (retained evidence: /tmp/mp3wat-fWpcBD). Repeat CAREFREE.MP3 on the same
GEOS setup to compare against the user's 156-second baseline. No new GEOS
runtime or speedup claim is made from the DOS checks.

Remaining measured DSP work can be tuned inside MP3DspCode without changing
the public decoder API or introducing per-product GEOS calls.

Optional mono output can mix after both channels' IMDCT and before polyphase
synthesis to avoid one synthesis path. It still needs both channels' entropy
decoding, stereo reconstruction and overlap history. Averaging finished PCM
saves output bandwidth only. Earlier spectral mixing needs explicit treatment
of differing block/window modes. No mono-output API change was made.

MMX/SIMD and an FPU backend remain separate optional work. They require
numerical review and verified GEOS context preservation; the current backend
uses 386 integer instructions and needs no coprocessor.

## Long manual music sample

Document/MP3TEST/CAREFREE.MP3 in the target installation is the original
"Carefree" by Kevin MacLeod (incompetech.com), licensed under
[Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
The [track page](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400037)
links the [original MP3](https://incompetech.com/music/royalty-free/mp3-royaltyfree/Carefree.mp3).
The target's CAREFREE.TXT contains attribution and the download checksum.
The audio is not transcoded or stored in this source repository.

FFprobe reports 205.139625 seconds, 44100 Hz, stereo, 256 kbit/s, 6566713 bytes.
FFmpeg decodes the complete download without reported errors. Use a new output
name such as CAREFREE.WAV; compare conversion time with the app's decoded audio
duration, which includes the decoder's untrimmed MP3 padding.
