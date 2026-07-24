# WebPImport

The WebP library incrementally imports static lossy WebP images into a 24-bit
complex HugeBitmap.

## Supported input

The decoder accepts one VP8 keyframe in a RIFF/WEBP container. A VP8X chunk is
accepted when it describes the same canvas and does not request alpha or
animation. ICC, EXIF, XMP, and unknown bounded chunks are validated and
ignored. VP8L, alpha, animation, multiple image payloads, and dimensions above
2048 pixels are rejected.

## WebPImportBegin

WebPImportBegin seeks the source to zero, validates the container and VP8
header, allocates decoder storage, and creates a BMC_PACKBITS
BMF_24BIT | BMT_COMPLEX HugeBitmap. It does not decode macroblocks.

All output pointers are required and initialized before parsing. On success,
the caller owns the returned bitmap. On failure, the routine releases all
storage and VM chains it created.

The source and destination handles remain caller-owned. The source must remain
open and must not be used concurrently until WebPImportDestroy. Its final file
position is unspecified.

## WebPImportNext

Each call decodes one macroblock row. WEBP_RESULT_OK returns the exact
contiguous finalized range in firstLine and lineCount. The final range is
returned with WEBP_RESULT_OK; the following call returns WEBP_RESULT_DONE and
zero lines. Finalized RGB scanlines are PackBits-compressed as they are
appended to the bitmap.

After a decoding error, the decoder is terminal and later calls return
WEBP_ERROR_BAD_STATE.

## WebPImportDestroy

WebPImportDestroy accepts NullHandle and releases only decoder storage. It
does not close the source or free a bitmap returned by a successful Begin.
Free an unwanted complete or partial bitmap with VMFreeVMChain.
