#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile
import textwrap

def write_file(path, content):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)

def process_svg_style(source_path, dest_path):
    processed_lines = []
    with open(source_path, "r", encoding="utf-8") as source:
        for line in source:
            stripped = line.lstrip()
            if stripped.startswith("@include"):
                continue
            if stripped.startswith("#include"):
                continue
            processed_lines.append(line.replace("@SvgNamedColors", "SvgNamedColors"))
    write_file(dest_path, "".join(processed_lines))

def create_shim_header(path):
    shim = textwrap.dedent(
        """
        #ifndef SVG_STYLE_TEST_SHIM_H
        #define SVG_STYLE_TEST_SHIM_H
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <strings.h>
        #include <ctype.h>
        typedef unsigned char byte;
        typedef unsigned short word;
        typedef unsigned long dword;
        typedef long sdword;
        typedef unsigned long WWFixedAsDWord;
        typedef int Boolean;
        typedef void* MemHandle;
        #define TRUE 1
        #define FALSE 0
        #define NullHandle ((MemHandle)0)
        #define HF_DYNAMIC 0
        #define HAF_ZERO_INIT 0
        #define CF_RGB 0
        #define ODD_EVEN 0
        #define WINDING 0
        #define LE_ROUNDCAP 0
        #define LE_SQUARECAP 0
        #define LE_BUTTCAP 0
        #define LJ_ROUND 0
        #define LJ_BEVELED 0
        #define LJ_MITERED 0
        #define SVG_STYLE_GSTACK_MAX 16
        typedef struct {
            Boolean fillSet, strokeSet, swSet;
            char fillVal[64], strokeVal[64];
            WWFixedAsDWord strokeWidth;
            Boolean frSet;  byte fr;
            Boolean lcSet;  byte lc;
            Boolean ljSet;  byte lj;
            Boolean colorSet;
            char colorVal[64];
        } SvgGroupStyle;
        typedef struct {
            byte SNC_r;
            byte SNC_g;
            byte SNC_b;
            char SNC_name[33];
        } SvgNamedColor;
        static SvgNamedColor SvgNamedColors[1];
        static inline MemHandle MemAlloc(word bytes, word flags, word attrs)
        {
            (void)flags;
            (void)attrs;
            return calloc(1, bytes);
        }
        static inline void* MemLock(MemHandle mh)
        {
            return mh;
        }
        static inline void MemUnlock(MemHandle mh)
        {
            (void)mh;
        }
        static inline void MemFree(MemHandle mh)
        {
            free(mh);
        }
        static inline MemHandle OptrToHandle(void *ptr)
        {
            (void)ptr;
            return NullHandle;
        }
        static inline void ObjLockObjBlock(MemHandle mh)
        {
            (void)mh;
        }
        static inline word ChunkArrayGetCount(void *array)
        {
            (void)array;
            return 0;
        }
        static inline void* ChunkArrayElementToPtr(void *array, word index, word *elemSize)
        {
            (void)array;
            (void)index;
            if (elemSize != NULL) {
                *elemSize = 0;
            }
            return NULL;
        }
        static inline const char* SvgParserSkipWS(const char *p)
        {
            while (p != NULL && *p && isspace((unsigned char)*p)) {
                p++;
            }
            return p;
        }
        static inline Boolean SvgUtilAsciiNoCaseEq(const char *a, const char *b)
        {
            if (a == NULL || b == NULL) {
                return FALSE;
            }
            while (*a && *b) {
                if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) {
                    return FALSE;
                }
                a++;
                b++;
            }
            return (*a == 0 && *b == 0);
        }
        static inline word SvgUtilHexNibble(char c)
        {
            if (c >= '0' && c <= '9') {
                return (word)(c - '0');
            }
            if (c >= 'a' && c <= 'f') {
                return (word)(c - 'a' + 10);
            }
            if (c >= 'A' && c <= 'F') {
                return (word)(c - 'A' + 10);
            }
            return 0;
        }
        static inline word SvgUtilHexByte(const char *p)
        {
            word hi = SvgUtilHexNibble(p[0]);
            word lo = SvgUtilHexNibble(p[1]);
            return (word)((hi << 4) | lo);
        }
        static inline Boolean SvgUtilExpandShortHex(const char *s, word *r, word *g, word *b)
        {
            if (s == NULL || s[0] != '#' || strlen(s) != 4) {
                return FALSE;
            }
            *r = (word)(SvgUtilHexNibble(s[1]) * 17);
            *g = (word)(SvgUtilHexNibble(s[2]) * 17);
            *b = (word)(SvgUtilHexNibble(s[3]) * 17);
            return TRUE;
        }
        static inline Boolean SvgUtilParseRGBFunc(const char *s, word *r, word *g, word *b)
        {
            (void)s;
            (void)r;
            (void)g;
            (void)b;
            return FALSE;
        }
        static inline const char* SvgUtilParseWWFixed16_16(const char *s, WWFixedAsDWord *out)
        {
            char *endPtr;
            long value;
            if (s == NULL || out == NULL) {
                return s;
            }
            value = strtol(s, &endPtr, 10);
            *out = (WWFixedAsDWord)((unsigned long)(value << 16));
            return endPtr;
        }
        static inline WWFixedAsDWord SvgGeomMakeWWFixedFromInt(int v)
        {
            return (WWFixedAsDWord)((unsigned long)(v << 16));
        }
        static inline void Meta_SetLineColor(word cf, word r, word g, word b)
        {
            (void)cf; (void)r; (void)g; (void)b;
        }
        static inline void Meta_SetAreaColor(word cf, word r, word g, word b)
        {
            (void)cf; (void)r; (void)g; (void)b;
        }
        static inline void Meta_SetFillRule(word rule)
        {
            (void)rule;
        }
        static inline void Meta_SetLineWidth(WWFixedAsDWord w)
        {
            (void)w;
        }
        static inline void Meta_SetLineEnd(word end)
        {
            (void)end;
        }
        static inline void Meta_SetLineJoin(word join)
        {
            (void)join;
        }
        static inline Boolean SvgParseGetInlineStyleProp(const char *tag, const char *prop,
                                                         char *out, word outSize)
        {
            const char *stylePos;
            const char *start;
            const char *end;
            size_t propLen;
            if (tag == NULL || prop == NULL || out == NULL || outSize == 0) {
                return FALSE;
            }
            stylePos = strstr(tag, "style=");
            if (stylePos == NULL) {
                return FALSE;
            }
            start = strchr(stylePos, '\"');
            if (start == NULL) {
                return FALSE;
            }
            start++;
            end = strchr(start, '\"');
            if (end == NULL) {
                return FALSE;
            }
            propLen = strlen(prop);
            while (start < end) {
                const char *segmentEnd;
                while (start < end && isspace((unsigned char)*start)) {
                    start++;
                }
                if ((size_t)(end - start) < propLen) {
                    break;
                }
                if (strncasecmp(start, prop, propLen) == 0 && start[propLen] == ':') {
                    start += propLen + 1;
                    while (start < end && isspace((unsigned char)*start)) {
                        start++;
                    }
                    segmentEnd = strchr(start, ';');
                    if (segmentEnd == NULL || segmentEnd > end) {
                        segmentEnd = end;
                    }
                    while (segmentEnd > start && isspace((unsigned char)segmentEnd[-1])) {
                        segmentEnd--;
                    }
                    if ((word)(segmentEnd - start) >= outSize) {
                        segmentEnd = start + (outSize - 1);
                    }
                    memcpy(out, start, (size_t)(segmentEnd - start));
                    out[segmentEnd - start] = 0;
                    return TRUE;
                }
                segmentEnd = strchr(start, ';');
                if (segmentEnd == NULL || segmentEnd >= end) {
                    break;
                }
                start = segmentEnd + 1;
            }
            return FALSE;
        }
        static inline Boolean SvgParserGetAttrBounded(const char *tag, const char *name,
                                                      char *out, word outSize)
        {
            const char *pos;
            const char *valueStart;
            const char *valueEnd;
            size_t nameLen;
            if (tag == NULL || name == NULL || out == NULL || outSize == 0) {
                return FALSE;
            }
            nameLen = strlen(name);
            pos = strstr(tag, name);
            if (pos == NULL) {
                return FALSE;
            }
            pos += nameLen;
            while (*pos && isspace((unsigned char)*pos)) {
                pos++;
            }
            if (*pos != '=') {
                return FALSE;
            }
            pos++;
            while (*pos && isspace((unsigned char)*pos)) {
                pos++;
            }
            if (*pos != '"' && *pos != (char)39) {
                return FALSE;
            }
            valueStart = ++pos;
            while (*pos && *pos != '"' && *pos != (char)39) {
                pos++;
            }
            if (*pos != '"' && *pos != (char)39) {
                return FALSE;
            }
            valueEnd = pos;
            if ((size_t)(valueEnd - valueStart) >= outSize) {
                valueEnd = valueStart + (outSize - 1);
            }
            memcpy(out, valueStart, (size_t)(valueEnd - valueStart));
            out[valueEnd - valueStart] = 0;
            return TRUE;
        }
        #endif
        """
    )
    write_file(path, shim)

def create_test_source(path):
    test_code = textwrap.dedent(
        """
        #include "shim.h"
        static void SvgStyleStackFree(void);
        static Boolean SvgStyleResolvePropWithGroups(const char *, const char *, char *, word, Boolean);
        static Boolean SvgStyleResolvePaintToSolidOrNone(const char *, const char *, const char *, word *, word *, word *);
        static Boolean SvgStyleResolveCurrentColor(const char *, word *, word *, word *);
        static void SvgStyleApplyStrokeCapJoin(const char *tag);
        #include "svgStyle_impl.c"
        static void assert_true(Boolean cond, const char *message)
        {
            if (!cond) {
                fputs(message, stderr);
                fputc(10, stderr);
                exit(1);
            }
        }
        int main(void)
        {
            word r;
            word g;
            word b;
            char buf[64];
            Boolean have;
            assert_true(SvgStyleStackInit(), "SvgStyleStackInit failed");
            SvgStyleGroupPush("<g fill='#010203' color='#445566'>");
            SvgStyleGroupPush("<g fill='inherit' stroke='currentColor'>");
            have = SvgStyleResolvePropWithGroups("<rect fill='inherit' stroke='currentColor'>",
                                                 "fill", buf, sizeof(buf), FALSE);
            assert_true(have, "fill inherit not found");
            have = SvgStyleResolvePaintToSolidOrNone("<rect fill='inherit' stroke='currentColor'>",
                                                     "fill", buf, &r, &g, &b);
            assert_true(have, "fill inherit did not resolve");
            assert_true(r == 1 && g == 2 && b == 3, "fill inherit wrong value");
            have = SvgStyleResolvePropWithGroups("<rect fill='inherit' stroke='currentColor'>",
                                                 "stroke", buf, sizeof(buf), FALSE);
            assert_true(have, "stroke currentColor not found");
            have = SvgStyleResolvePaintToSolidOrNone("<rect fill='inherit' stroke='currentColor'>",
                                                     "stroke", buf, &r, &g, &b);
            assert_true(have, "stroke currentColor did not resolve");
            assert_true(r == 0x44 && g == 0x55 && b == 0x66, "stroke currentColor wrong");
            SvgStyleGroupPop();
            SvgStyleGroupPop();
            SvgStyleGroupPush("<g>");
            have = SvgStyleResolvePropWithGroups("<line stroke='currentColor'>",
                                                 "stroke", buf, sizeof(buf), FALSE);
            assert_true(have, "stroke currentColor default not found");
            have = SvgStyleResolvePaintToSolidOrNone("<line stroke='currentColor'>",
                                                     "stroke", buf, &r, &g, &b);
            assert_true(have, "stroke currentColor default did not resolve");
            assert_true(r == 0 && g == 0 && b == 0, "default currentColor should be black");
            SvgStyleGroupPop();
            SvgStyleStackFree();
            return 0;
        }
        """
    )
    write_file(path, test_code)

def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".."))
    svg_style_path = os.path.join(repo_root, "Library", "Breadbox", "Meta", "SVG", "svgStyle.goc")
    with tempfile.TemporaryDirectory() as tmpdir:
        impl_path = os.path.join(tmpdir, "svgStyle_impl.c")
        shim_path = os.path.join(tmpdir, "shim.h")
        test_path = os.path.join(tmpdir, "test.c")
        binary_path = os.path.join(tmpdir, "svg_style_test")
        process_svg_style(svg_style_path, impl_path)
        create_shim_header(shim_path)
        create_test_source(test_path)
        compile_cmd = ["gcc", "-std=c99", "-Wall", "-Werror", test_path, "-o", binary_path]
        env = os.environ.copy()
        env["C_INCLUDE_PATH"] = tmpdir
        subprocess.run(compile_cmd, check=True, env=env)
        subprocess.run([binary_path], check=True, env=env)
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as err:
        print(f"Command failed: {err}", file=sys.stderr)
        sys.exit(1)
