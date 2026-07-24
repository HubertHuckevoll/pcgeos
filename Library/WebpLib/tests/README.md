# WebpLib host tests

The images directory contains lossy WebP inputs and matching reference RGB
outputs generated with Pillow and desktop libwebp. Each RGB file is tightly
packed red, green, blue data with no header or row padding.

The corpus covers small and odd dimensions, metadata, single-column images,
and widths and heights at the 2047 and 2048 pixel limits.

The `real-*` pairs provide recognizable color checks: a red apple with a green
leaf, a yellow duck on blue water, and a red-and-white lighthouse on green
grass beneath a blue sky.

Build and run the host checks from the repository root:

```sh
cc -std=c89 -Wall -Wextra -Werror -I Library/WebpLib \
    -o /tmp/webpbit_test Library/WebpLib/tests/webpbit_test.c
cc -std=c89 -Wall -Wextra -Werror -I Library/WebpLib \
    -o /tmp/webpriff_test Library/WebpLib/tests/webpriff_test.c
cc -std=c89 -Wall -Wextra -Werror -I Library/WebpLib \
    -o /tmp/webpdecode_test Library/WebpLib/tests/webpdecode_test.c

/tmp/webpbit_test
/tmp/webpriff_test
for image in Library/WebpLib/tests/images/*.webp; do
    stem=${image%.webp}
    /tmp/webpdecode_test "$image" /tmp/webpdecode.rgb
    cmp /tmp/webpdecode.rgb "$stem.rgb"
done
```
