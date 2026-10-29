# BSNWav PCM source interface

The playback boundary is **PCM source → BSNWav → BestSound driver**.

`BSNWavePlayFile()` still parses RIFF/WAVE and finds the PCM data chunk.
`BSNWReadPCM()` is the single read boundary used by `BSNWLoadCache()`:
- WAV file: exact-length file reads, with the caller-owned file handle.
- Legacy `BSNWavePlayCallback()`: exact-length Boolean callback, unchanged ABI.
- New `BSNWavePlayPCM()`: count-returning callback and opaque caller context.

The rest of the pipeline (`BSNWLoadData`, conversions, secondary buffer,
driver strategy calls, DMA interrupts) remains unchanged except for
short-stream draining and proper source-error propagation.

## New public call

```c
BSNWavePlayPCM(BSWavFormChunk *format,
               dword decodedPCMBytes,
               word flags,
               optr parent,
               void *context,
               PCB(word, reader, (void *, void *, word)));
```

The Pascal callback has the signature:

```c
word _pascal Reader(void *context, void *destination, word maxBytes);
```

Its result is:
- **1..maxBytes**: valid decoded PCM bytes; short positive reads are legal.
- **0**: EOF (the playback engine drains already queued samples).
- **BSNW_PCM_READ_ERROR (0xffff)**: a source/decoder error.

Return only complete interleaved PCM frames. No callback should write beyond
`maxBytes`. The playback engine requests frame-aligned byte counts and checks
that returned counts are frame-aligned.

`decodedPCMBytes` may be `BSNW_PCM_LENGTH_UNKNOWN` (0xffffffffUL) for a
stream of unknown size, or an exact/estimated decoded length. For a known
length, the engine stops at that limit, but early EOF is also valid.
An empty stream can return EOF immediately.

`format` describes **decoded PCM**, not the MP3 file: use PCM format ID 1,
8/16 bits, 1/2 channels, `blockAlign = channels * (bits / 8)`, and
`avgRate = sampleRate * blockAlign`. The existing output hardware validation
still limits playable rates (currently below 44,200 Hz; 48 kHz is **not**
enabled by this refactor).

## Ownership and threading

The call is blocking. The caller creates/owns its playback thread and must
keep the reader routine and context valid until the call returns. The source
owns its file handle and decoder state; BSNWav owns the play cache, and the
BestSound driver owns the secondary DMA buffer. The callback runs on the
playback thread, **never** from the DMA interrupt routine.

For MP3, the adapter should keep a decoded-frame staging buffer: it can
produce one frame, copy up to `maxBytes` into BSNWav, and retain the remainder
for the next call. It does not need to know the final decoded PCM length.

BSNWav remains a single-instance player (shared globals). There is no mixing
of independent PCM sources in this change.

## Validation

Run `python3 Library/Audio/BSNWav/tests/check_pcm_source.py` from a checkout
with a host C compiler (`cc`). The script extracts the **actual**
`BSNWLoadCache()` function body and compiles it against stubbed source reads.
It covers unknown/known lengths, short reads, early EOF, source errors,
invalid byte counts, and ring-buffer wraparound.

These are logic tests, **not** a Watcom/GEOS build or actual driver/audio
playback test. WAV playback with both BSD16 and BSD8ST still needs verification
in GEOS, especially pause/stop and short-file tail draining.
