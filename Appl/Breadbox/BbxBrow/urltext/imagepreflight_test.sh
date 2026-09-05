#!/bin/sh
set -eu

src=`dirname "$0"`/URLTEXT.goc
tmp=`mktemp -d /tmp/pcgeos-image-preflight.XXXXXX`
trap 'rm -rf "$tmp"' 0 1 2 3 15

sed -n '/^word _pascal URLTextImageFormatFromMime(TCHAR \*mimeType)$/,/^extern void _pascal WakeUp/p' "$src" |
    sed '$d' > "$tmp/format.inc"
sed -n '/^#define IMAGE_URL_EXTENSION_MAX 16$/,/^void IReplaceGraphic(optr oself/p' "$src" |
    sed '$d' > "$tmp/helper.inc"

cat > "$tmp/check.c" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <stdlib.h>

typedef unsigned char byte;
typedef unsigned short word;
typedef const char *NameToken;
typedef unsigned short optr;
typedef int Boolean;
typedef char TCHAR;
typedef char FileLongName[64];

#define TRUE 1
#define FALSE 0
#define _pascal
#define _TEXT(s) s
#define HTML_STATIC_BUF 256
#define MIME_MAXBUF 80
#define HTML_IDF_FORMAT_MASK 0x0380
#define HTML_IDF_FORMAT_JPEG 0x0080
#define HTML_IDF_FORMAT_PNG  0x0100
#define HTML_IDF_FORMAT_GIF  0x0180
#define HTML_IDF_FORMAT_WEBP 0x0200
#define HTML_IDF_FORMAT_SVG  0x0280
#define strcmpi strcasecmp

static int LocalCmpStringsNoCase(const char *left, const char *right,
                                 word length)
{
    return strncasecmp(left, right, length);
}

static char *host_strupr(char *s)
{
    char *p;

    for (p = s; *p; p++) {
        if (*p >= 'a' && *p <= 'z')
            *p = (char)(*p - ('a' - 'A'));
    }
    return s;
}

#define strupr host_strupr

static optr assocExtType = 1;
static optr assocTypeDriver = 2;
static optr namePool = 3;

typedef struct {
    const char *extension;
    const char *mime;
} ExtensionAssociation;

static const ExtensionAssociation extensions[] = {
    { "BMP", "image/bmp" },
    { "GIF", "image/gif" },
    { "JPG", "image/jpeg" },
    { "PNG", "image/png" },
    { "SVG", "image/svg+xml" },
    { "WEBP", "image/webp" },
    { "TXT", "text/plain" },
    { (const char *)0, (const char *)0 }
};

static const char *drivers[] = {
    "image/gif",
    "image/jpeg",
    "image/png",
    (const char *)0
};

static Boolean webpDriver = TRUE;

static void NamePoolCopy(optr pool, TCHAR *dst, word dstSize,
                         NameToken token, TCHAR **resultP)
{
    (void)pool;
    (void)token;
    strncpy(dst, (const char *)token, dstSize - 1);
    dst[dstSize - 1] = 0;
    *resultP = dst;
}

static void NamePoolDestroyIfDynamic(TCHAR *p)
{
    (void)p;
}

static Boolean NameAssocFindAssociation(optr assoc, TCHAR *key, TCHAR *value,
                                        word valueSize, Boolean exact,
                                        void *unused)
{
    const ExtensionAssociation *extP;
    const char **driverP;

    (void)exact;
    (void)unused;
    if (assoc == assocExtType) {
        for (extP = extensions; extP->extension; extP++) {
            if (!strcasecmp(key, extP->extension)) {
                strncpy(value, extP->mime, valueSize - 1);
                value[valueSize - 1] = 0;
                return TRUE;
            }
        }
    } else if (assoc == assocTypeDriver) {
        for (driverP = drivers; *driverP; driverP++) {
            if (!strcasecmp(key, *driverP)) {
                strncpy(value, "mock-driver", valueSize - 1);
                value[valueSize - 1] = 0;
                return TRUE;
            }
        }
        if (webpDriver && !strcasecmp(key, "image/webp")) {
            strncpy(value, "mock-driver", valueSize - 1);
            value[valueSize - 1] = 0;
            return TRUE;
        }
    }
    return FALSE;
}

#include "format.inc"
#include "helper.inc"

static Boolean check(const char *url, Boolean expectedUnsupported,
                     word expectedFormat)
{
    Boolean unsupported;
    word format;

    unsupported = ImageURLGetUnsupportedFormat((NameToken)url, &format);
    if (unsupported != expectedUnsupported || format != expectedFormat) {
        fprintf(stderr, "failed: %s (unsupported=%u format=0x%04x)\n",
                url, unsupported, format);
        return FALSE;
    }
    return TRUE;
}

int main(void)
{
    if (!check("https://example.test/image.BMP", TRUE, 0))
        return 1;
    if (!check("https://example.test/image.jpg", FALSE,
               HTML_IDF_FORMAT_JPEG))
        return 1;
    if (!check("https://example.test/image.gif", FALSE,
               HTML_IDF_FORMAT_GIF))
        return 1;
    if (!check("https://example.test/image.svg#frag?query", TRUE,
               HTML_IDF_FORMAT_SVG))
        return 1;
    webpDriver = FALSE;
    if (!check("https://example.test/image.WeBp?x=1#frag", TRUE,
               HTML_IDF_FORMAT_WEBP))
        return 1;
    webpDriver = TRUE;
    if (!check("https://example.test/image.WeBp?x=1#frag", FALSE,
               HTML_IDF_FORMAT_WEBP))
        return 1;
    if (!check("https://example.test/image.png?x=1", FALSE,
               HTML_IDF_FORMAT_PNG))
        return 1;
    if (!check("https://example.test/image.txt", FALSE, 0))
        return 1;
    if (!check("https://example.test/path.svg/image", FALSE, 0))
        return 1;
    if (!check("https://example.test/image.unknown", FALSE, 0))
        return 1;
    if (!check("https://example.test/image.svgx", FALSE, 0))
        return 1;
    puts("image preflight checks passed");
    return 0;
}
EOF

cc -std=c89 -Wall -Wextra -pedantic "$tmp/check.c" -o "$tmp/check"
"$tmp/check"
