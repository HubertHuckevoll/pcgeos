# Plan: Add automatic JPEG downscaling to IMPGRAPH

## Goal

Allow IMPGRAPH to import oversized JPEG images by using IJG JPEG’s native IDCT scaling before bitmap allocation.

Target a maximum output dimension of approximately 800 pixels while preserving aspect ratio. Supported scaling factors are `1/1`, `1/2`, `1/4`, and `1/8`.

Gate this behaviour behind a Compile flag, that is set to TRUE by default. Restrict this scaling to JPEG.

## Primary file

`Library/Breadbox/ImpGraph/IMPBMP/impjpeg.goc`

Modify `JpegImport()`.

## Implementation steps

### 1. Configure scaling after reading the JPEG header

Immediately after:

```c
headerErr = (jpeg_read_header(cinfo, TRUE) == JPEG_SUSPENDED);
```

determine the longest image dimension and choose the smallest supported denominator that reduces it to 800 pixels or less:

```c
#define JPEG_TARGET_MAX 800

word denom = 1;
dword longest;

if (!headerErr) {
    longest = cinfo->image_width;

    if (cinfo->image_height > longest)
        longest = cinfo->image_height;

    while ((denom < 8) &&
           (((longest + denom - 1) / denom) > JPEG_TARGET_MAX)) {
        denom <<= 1;
    }

    cinfo->scale_num = 1;
    cinfo->scale_denom = denom;

    jpeg_calc_output_dimensions(cinfo);
}
```

Do not upscale images already below the target size.

Avoid relying on a `max()` macro unless one is already safely available in this compilation unit.

### 2. Return the scaled dimensions

Replace:

```c
picsize->XYS_width = cinfo->image_width;
picsize->XYS_height = cinfo->image_height;
```

with:

```c
picsize->XYS_width = cinfo->output_width;
picsize->XYS_height = cinfo->output_height;
```

The browser and progress callbacks must see the actual imported bitmap dimensions.

### 3. Apply size limits to scaled output

Replace the existing rejection test based on `picsize` or `image_width/image_height` with one based on:

```c
cinfo->output_width
cinfo->output_height
```

For example:

```c
if (headerErr == FALSE &&
    gotTempAlloc &&
    cinfo->output_width <= 2048 &&
    cinfo->output_height <= 2048 &&
    ((dword)cinfo->output_width *
     (dword)cinfo->output_height <= 1024L * 1024L)) {
```

This ensures that large source JPEGs are accepted when their scaled output fits IMPGRAPH’s limits.

### 4. Calculate output dimensions unconditionally

There is currently another call to:

```c
jpeg_calc_output_dimensions(cinfo);
```

inside the color-quantization branch:

```c
if (displayClass != DC_CF_RGB)
```

Remove that call after moving dimension calculation to the common code after `jpeg_read_header()`.

Output dimensions must be calculated for both paletted and 24-bit imports.

### 5. Preserve original dimensions for progressive-memory estimation

Do not change:

```c
cinfo->image_width
cinfo->image_height
```

in the progressive JPEG temporary-memory estimate.

IDCT scaling reduces the decoded output but does not necessarily reduce storage required for progressive JPEG coefficient data.

### 6. Verify downstream dimension usage

Confirm that all bitmap creation, memory accounting, scanline allocation, compression and progress reporting use:

```c
cinfo->output_width
cinfo->output_height
```

Most of the existing IJG importer already does this.

Check especially:

* `requiredMemory`
* `GrCreateBitmapRaw()`
* compressed bitmap header width
* scanline buffer size
* `row_stride`
* progress callback image dimensions

Do not convert these back to `image_width` or `image_height`.

## FJPEG path

`ImpJPG()` may try `FJpegImport()` before `JpegImport()` when `PRODUCT_FJPEG` is enabled.

FJPEG has its own original-size rejection and does not appear to expose equivalent IDCT scaling. It may simply fail and fall back to the IJG importer.

For the first implementation:

* modify only `JpegImport()`;
* confirm that failed FJPEG imports reliably fall back to IJG;
* do not duplicate the scaling work in `impfjpeg.goc` unless necessary.

## Behaviour examples

| Source     | Selected scale |             Imported size |
| ---------- | -------------: | ------------------------: |
| 700×500    |            1/1 |                   700×500 |
| 1200×800   |            1/2 |                   600×400 |
| 3000×2000  |            1/4 |                   750×500 |
| 6000×4000  |            1/8 |                   750×500 |
| 12000×9000 |            1/8 | 1500×1125, still rejected |

Exact 800-pixel output is not possible with native IJG scaling alone. The purpose is efficient coarse downscaling before full decompression.

## Tests

Test at least:

1. JPEG below 800 pixels: imported unchanged.
2. Landscape JPEG requiring `1/2`.
3. Portrait JPEG requiring `1/4`.
4. Large modern camera JPEG requiring `1/8`.
5. Image still too large after `1/8`: rejected cleanly.
6. Grayscale JPEG.
7. 24-bit RGB JPEG.
8. Quantized 8-bit or 4-bit output.
9. Baseline JPEG.
10. Progressive JPEG, including low-memory failure behaviour.
11. Browser streaming/progress import.
12. Import with scanline compression enabled and disabled.

## Acceptance criteria

* Large baseline JPEGs are no longer rejected solely because of their original dimensions.
* The imported bitmap’s longest side is at most about 800 pixels whenever `1/8` scaling is sufficient.
* Aspect ratio is preserved.
* Small JPEGs remain unchanged.
* Bitmap dimensions, allocation sizes and progress information match the scaled output.
* Existing GIF and PNG import behaviour is unaffected.
* Progressive JPEG memory accounting remains conservative.
