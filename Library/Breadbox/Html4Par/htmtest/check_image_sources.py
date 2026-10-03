#!/usr/bin/env python3
"""Exercise the actual selectors, picture handlers and ParseImage on the host."""

from html.parser import HTMLParser
from pathlib import Path
import json
import re
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
source = (root / "htmlpars/opentags.goc").read_bytes().decode("latin1")
browser = (root.parents[2] / "Appl/Breadbox/BbxBrow/urlframe/FRFETCH.goc").read_bytes().decode("latin1")


def function(text, name):
    start = re.search(r"^(?:[A-Za-z_][^\n]*\b)?" + name + r"\([^;{]*\)\s*\{", text, re.M).start()
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


harness = r'''
#include <assert.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned short word;
typedef unsigned int dword;
typedef dword WWFixedAsDWord;
typedef int Boolean;
typedef word NameToken;
typedef char TCHAR;
typedef struct { const char *key, *value; } Param;
typedef Param *optr;
typedef struct { optr paramArray; word spec; } TagOpenArguments;
typedef Boolean proc_HTMLImageMimeSupported(char *mimeP);
typedef Boolean pcfm_HTMLImageMimeSupported(char *mimeP, void *callbackP);
typedef struct {
    optr view;
    proc_HTMLImageMimeSupported *mimeSupported;
} HTMLImageSourceContext;
typedef struct { int RD_left, RD_right; } RectDWord;
typedef struct {
    word viewportWidth;
    proc_HTMLImageMimeSupported *mimeSupported;
    Boolean inPicture;
    NameToken pictureSource;
} HTMLImageSourceState;
typedef char FileLongName[40];
#define MIME_MAXBUF 128
#define _TEXT(s) s
#define LOCAL
#define _pascal
#define _export
#define TRUE 1
#define FALSE 0
#define NAME_POOL_NONE 0
#define STRCMPSB strcmp
#define STRLENSB strlen
#define ATOISB atoi
#define IS_SRCSET_SPACE(c) \
    ((c) == ' ' || (c) == '\t' || (c) == '\n' || (c) == '\f' || (c) == '\r')
static HTMLImageSourceState imageSourceState;
static RectDWord viewRect;
static unsigned viewQueries;
static void GetVisibleRect(optr view, RectDWord *visible)
{
    assert(view);
    *visible = viewRect;
    viewQueries++;
}
static optr NamePool, assocTypeDriver;
static char names[512][4096];
static unsigned refs[512], nextToken, supportWebp;
static word currentFlags, G_imageCount, G_imageLimit = 200, svgImageIndex;
static int c2;
static char *GetParamValue(optr p, const char *key)
{
    for(; p && p->key; p++)
        if(!strcmp(p->key, key)) return (char *)p->value;
    return (char *)0;
}
static NameToken NamePoolTokenizeLenDOS(optr pool, char *s, word n, Boolean required)
{
    (void)pool; (void)required;
    if(!n) n = (word)strlen(s);
    assert(n < sizeof(names[0]) && nextToken + 1 < 512);
    nextToken++;
    memcpy(names[nextToken], s, n);
    names[nextToken][n] = 0;
    refs[nextToken] = 1;
    return (NameToken)nextToken;
}
#define NamePoolTokenizeDOS(pool, s, required) NamePoolTokenizeLenDOS(pool, s, 0, required)
static void NamePoolReleaseToken(optr pool, NameToken token)
{
    (void)pool;
    assert(token && refs[token]);
    refs[token]--;
}
static int LocalCmpStringsNoCase(const char *a, const char *b, unsigned n)
{
    unsigned i;
    for(i = 0; i < n; i++)
        if(tolower((unsigned char)a[i]) != tolower((unsigned char)b[i])) return 1;
    return 0;
}
static Boolean NameAssocFindAssociation(optr a, const char *mime, char *driver,
    unsigned n, Boolean insensitive, void *unused)
{
    (void)a; (void)driver; (void)n; (void)insensitive; (void)unused;
    return !strcmp(mime, "image/jpeg") || !strcmp(mime, "image/gif") ||
           !strcmp(mime, "image/png") || !strcmp(mime, "image/svg+xml") ||
           (supportWebp && !strcmp(mime, "image/webp"));
}
static Boolean ProcCallFixedOrMovable_pascal(char *mime, void *callback)
{
    return ((proc_HTMLImageMimeSupported *)callback)(mime);
}
/* GEOS LocalAsciiToFixed consumes a decimal mantissa, not its exponent. */
static dword LocalAsciiToFixed(char *p, char **end)
{
    double value = 0, place = .1;
    while(isdigit((unsigned char)*p)) value = value * 10 + (*p++ - '0');
    if(*p == '.') {
        p++;
        while(isdigit((unsigned char)*p)) {
            value += (*p++ - '0') * place;
            place /= 10;
        }
    }
    *end = p;
    return value >= 32768 ? 0xffffffffU : (dword)(value * 65536 + .5);
}
typedef struct { word XYS_width, XYS_height; } XYSize;
typedef short sword;
typedef struct { word WWF_frac; sword WWF_int; } WWFixed;
#define MakeWWFixed(n) ((dword)(n) << 16)
#define FractionOf(n) ((word)(n))
#define IntegerOf(n) ((sword)((n) >> 16))
static dword GrUDivWWFixed(dword a, dword b)
{ return (dword)((double)a * 65536 / b); }
static dword GrMulWWFixed(dword a, dword b)
{ return (dword)(int)((double)(int)a * (int)b / 65536); }
typedef struct {
    struct { word WBF_frac, WBF_int; } VTCA_pointSize;
    word VTCA_fontID, VTCA_extendedStyles;
} VisTextCharAttr;
typedef struct {
    NameToken name, imageURL, imageALT, usemap;
    word flags, pos, len, formElementIndex, hspace, vspace;
    XYSize size, HID_size;
    WWFixed HID_tmatrixE11, HID_tmatrixE22;
    struct { sword XYO_x, XYO_y; } HID_drawOffset;
    struct { int P_x, P_y; } HID_pos;
} HTMLimageData;
typedef struct { word HIGV_imageIndex; } HTMLimageGraphicVariable;
typedef struct {
    XYSize VTG_size;
    word VTG_type;
    struct { struct {
        word VTGV_manufacturerID, VTGV_type, VTGV_privateData[4];
    } VTGD_variable; } VTG_data;
} VisTextGraphic;
static struct { word TTBH_graphicElements, TTBH_graphicRuns; } header, *ttbh = &header;
static struct { word HCD_hardMinWidth, HCD_minHeight; } insertCellData;
static VisTextCharAttr currentCS;
static HTMLimageData captured;
static VisTextGraphic graphic;
#define TAG_FLUSH_TEXT 1
#define CA_NULL_ELEMENT 0xffff
#define DEFAULT_IMAGE_LIMIT 200
#define C_GRAPHIC 1
#define C_SUBSTITUTE 1
#define VTES_NOWRAP 1
#define FID_DTC_URW_MONO 1
#define HTML_IDF_INLINE_SVG 1
#define HTML_IDF_PICTURE 0x1000
#define HTML_IDF_SUBMIT 2
#define HTML_IDF_ISMAP 4
#define HTML_LEN_GET_UNIT(n) ((n) & 0xc000)
#define HTML_LEN_PIXEL 0
#define DEFAULT_IMAGE_HEIGHT 20
#define DEFAULT_IMAGE_WIDTH 20
#define VTGT_VARIABLE 1
#define HTML_VARGRAPH_MFGID 1
#define HTML_VARGRAPH_TYPE_IMAGE 1
#define IMAGE_HEIGHT_FUDGE_FACTOR 2
#define HTA_IMAGE_ARRAY 1
static Boolean InitFileReadInteger(char *category, char *key, word *v)
{ (void)category; (void)key; (void)v; return TRUE; }
static void AddParaCond(void) {}
static void GetCharacterBase(VisTextCharAttr *a) { memset(a, 0, sizeof(*a)); }
static word AddText(VisTextCharAttr *a, char *s) { (void)a; (void)s; return 0; }
static word ParseMultiLength(char *s, word unused) { (void)unused; return (word)atoi(s); }
static word AppendToHypertextArray(word type, HTMLimageData *id)
{ (void)type; captured = *id; return G_imageCount; }
static void AddAttrRun(word elements, word runs, VisTextGraphic *g, word pos)
{ (void)elements; (void)runs; (void)pos; graphic = *g; }
'''

display = (root / "htmlclas/htmlclas.goc").read_bytes().decode("latin1")
for name, result in (("HTMLTextScaleDrawOffset", "sword"),
                     ("HTMLTextFitImageToViewport", "Boolean")):
    harness += "static " + result + " _pascal " + function(display, name) + "\n"

for name in ("FrameImageMimeSupported",):
    harness += function(browser, name) + "\n"
for name in ("ParseSrcsetDensity", "SelectSrcsetCandidate", "ClearPicture",
             "PictureBeforeTag", "PictureText", "TakePictureSource",
             "PictureMediaMatches", "Open_PICTURE", "Open_SOURCE", "ParseImage"):
    harness += function(source, name) + "\n"
harness += r'''
#define SPEC_TABLE 1
#define SPEC_TR 2
#define SPEC_TD 3
#define SPEC_IMG 4
#define SPEC_SVG 5
#define TAG_IS_PAR_STYLE 1
#define HTML_MAXTABLE 16
#define HTML_EVENT_OBJECT_IMAGE 1
#define OptrToChunk(v) 0
#define LMemDeref(v) ((void *)(v))
typedef struct { char *name; word ca, pa, spec, flags; } HTMLStylesTable;
typedef struct { struct { word HTD_width, HTD_cellpadding, HTD_cellspacing; } tableData; } TableStackElement;
static TableStackElement tables[HTML_MAXTABLE + 1];
optr tableStackO = (optr)tables;
static word tableDepth, eventCalls;
static int STRCMPISB(char *a, char *b)
{
    while(*a && *b && tolower((unsigned char)*a) == tolower((unsigned char)*b)) { a++; b++; }
    return *a || *b;
}
static optr IDupLMem(optr params) { return params; }
static word EnclosingCount(word spec, void *unused) { (void)spec; (void)unused; return tableDepth; }
static void ParseEvents(optr params, word type, word index)
{
    (void)type; (void)index;
    if(GetParamValue(params, "ONLOAD")) eventCalls++;
}
void Open_IMG(TagOpenArguments *arg);
static void OpenTag(word spec, HTMLStylesTable *style, optr params)
{
    TagOpenArguments arg;
    (void)style;
    if(spec == SPEC_TABLE) tableDepth++;
    if(spec == SPEC_IMG) { arg.spec = spec; arg.paramArray = params; Open_IMG(&arg); }
}
static void CloseTag(word spec, HTMLStylesTable *style, optr params)
{
    (void)style; (void)params;
    if(spec == SPEC_TABLE) tableDepth--;
}
'''
open_image = function(source, "Open_IMG").replace("static insideHere", "static int insideHere")
harness += re.sub(r"//[^\n]*", "", open_image) + "\n"
harness = re.sub(r"@ifdef (\w+)", r"#ifdef \1", harness).replace("@else", "#else").replace("@endif", "#endif")
# Compile the actual parse-start snapshot with only its GEOS message stubbed.
parser = (root / "htmlpars/htmlpars.goc").read_bytes().decode("latin1")
core = function(parser, "ParseHTMLFileWithImageSources")
snapshot = core[core.index("    memset(&imageSourceState"):core.index("    G_isParsing = TRUE")]
snapshot = snapshot.replace("@call imageSourcesP->view::MSG_GEN_VIEW_GET_VISIBLE_RECT(&visible);",
                            "GetVisibleRect(imageSourcesP->view, &visible);")
harness += "static void snapshot(HTMLImageSourceContext *imageSourcesP)\n{\nRectDWord visible; dword viewportWidth;\n" + snapshot + "}\n"
harness += r'''
static void releaseImage(void)
{
    if(captured.name) NamePoolReleaseToken(NamePool, captured.name);
    if(captured.imageURL) NamePoolReleaseToken(NamePool, captured.imageURL);
    if(captured.imageALT) NamePoolReleaseToken(NamePool, captured.imageALT);
    if(captured.usemap) NamePoolReleaseToken(NamePool, captured.usemap);
    memset(&captured, 0, sizeof(captured));
}
static void checkLeaks(void)
{
    unsigned i;
    ClearPicture();
    for(i = 1; i <= nextToken; i++) assert(!refs[i]);
    nextToken = 0;
}
static void candidate(char *set, char *src, word width, const char *expected)
{
    word n = 999;
    char *p = SelectSrcsetCandidate(set, src, width, &n);
    if(expected) assert(p && n == strlen(expected) && !memcmp(p, expected, n));
    else assert(!p && !n);
}
static void image(Param *params, const char *expected)
{
    TagOpenArguments arg;
    word count, events;
    Boolean picture;
    arg.paramArray = params; arg.spec = SPEC_IMG;
    count = G_imageCount; events = eventCalls;
    picture = imageSourceState.inPicture;
    Open_IMG(&arg);
    assert(G_imageCount == count + 1 && !tableDepth);
    assert(!strcmp(names[captured.imageURL], expected));
    assert(!!(captured.flags & HTML_IDF_PICTURE) == picture);
    assert(!imageSourceState.inPicture && !imageSourceState.pictureSource);
    if(GetParamValue(params, "WIDTH")) {
        assert(captured.size.XYS_width == 40 && captured.size.XYS_height == 20);
        assert(captured.hspace == 2 && captured.vspace == 3);
        assert(!strcmp(names[captured.imageALT], "Selected picture"));
        assert(!strcmp(names[captured.usemap], "#map"));
        assert(captured.flags & HTML_IDF_ISMAP);
        assert(graphic.VTG_size.XYS_width == 44);
        assert(eventCalls == events + 1);
    }
    releaseImage();
}
static void fitChecks(void)
{
    HTMLimageData image;

    memset(&image, 0, sizeof(image));
    image.flags = HTML_IDF_PICTURE;
    image.HID_tmatrixE11.WWF_int = image.HID_tmatrixE22.WWF_int = 1;
    image.HID_size.XYS_width = 768; image.HID_size.XYS_height = 432;
    image.hspace = 2;
    assert(HTMLTextFitImageToViewport(&image, 640, 200, 10));
    assert(image.HID_size.XYS_width == 625 && image.HID_size.XYS_height == 352);
    assert(image.hspace == 2);
    assert(!HTMLTextFitImageToViewport(&image, 640, 200, 10));
    assert(!HTMLTextFitImageToViewport(&image, 800, 200, 10));
    assert(image.HID_size.XYS_width == 625);
    assert(HTMLTextFitImageToViewport(&image, 400, 200, 10));
    assert(image.HID_size.XYS_width == 385 && image.HID_size.XYS_height == 217);
    assert(HTMLTextFitImageToViewport(&image, 1, 1, 65535));
    assert(image.HID_size.XYS_width == 1 && image.HID_size.XYS_height == 1);
    assert(!image.hspace);

    memset(&image, 0, sizeof(image));
    image.flags = HTML_IDF_PICTURE;
    image.HID_size.XYS_width = 100; image.HID_size.XYS_height = 1000;
    assert(!HTMLTextFitImageToViewport(&image, 640, 200, 10));
    image.flags = HTML_IDF_INLINE_SVG;
    image.HID_tmatrixE11.WWF_int = image.HID_tmatrixE22.WWF_int = 1;
    assert(HTMLTextFitImageToViewport(&image, 640, 200, 10));
    assert(image.HID_size.XYS_width == 20 && image.HID_size.XYS_height == 200);
}
static void unitChecks(void)
{
    TagOpenArguments arg;
    NameToken token;
    char transientURL[] = "selected";
    Param offered[] = {{"SRCSET", 0}, {0, 0}};
    Param typed[] = {{"TYPE", "image/jpeg"}, {"SRCSET", "typed"}, {0, 0}};
    Param fallback[] = {{"SRC", "fallback"}, {0, 0}};
    Param aligned[] = {{"SRC", "fallback"}, {"ALIGN", "left"}, {0, 0}};
    char mimeLong[140];
    HTMLImageSourceContext sources;
    Param news[8][4] = {
        {{"TYPE", "image/webp"}, {"MEDIA", "(max-width: 420px)"}, {"SRCSET", "news.webp?width=640"}, {0, 0}},
        {{"TYPE", "image/webp"}, {"MEDIA", "(max-width: 767px)"}, {"SRCSET", "news.webp?width=768"}, {0, 0}},
        {{"TYPE", "image/webp"}, {"MEDIA", "(max-width: 1023px)"}, {"SRCSET", "news.webp?width=960"}, {0, 0}},
        {{"TYPE", "image/webp"}, {"MEDIA", "(min-width: 1024px)"}, {"SRCSET", "news.webp?width=1280"}, {0, 0}},
        {{"TYPE", "image/jpeg"}, {"MEDIA", "(max-width: 420px)"}, {"SRCSET", "news.jpg?width=640"}, {0, 0}},
        {{"TYPE", "image/jpeg"}, {"MEDIA", "(max-width: 767px)"}, {"SRCSET", "news.jpg?width=768"}, {0, 0}},
        {{"TYPE", "image/jpeg"}, {"MEDIA", "(max-width: 1023px)"}, {"SRCSET", "news.jpg?width=960"}, {0, 0}},
        {{"TYPE", "image/jpeg"}, {"MEDIA", "(min-width: 1024px)"}, {"SRCSET", "news.jpg?width=1280"}, {0, 0}}
    };
    Param newsImage[] = {{"SRC", "news.jpg?width=1280"}, {0, 0}};
    word widths[] = {0, 400, 640, 800, 1024};
    word i, j, webp;
    const char *expected[2][5] = {
        {"news.jpg?width=1280", "news.jpg?width=640", "news.jpg?width=768", "news.jpg?width=960", "news.jpg?width=1280"},
        {"news.jpg?width=1280", "news.webp?width=640", "news.webp?width=768", "news.webp?width=960", "news.webp?width=1280"}
    };
    offered[0].value = transientURL;
    arg.paramArray = offered;
    assert(sizeof(word) == 2 && sizeof(dword) == 4);
    sources.view = (optr)1; sources.mimeSupported = FrameImageMimeSupported;
    viewRect.RD_left = 30; viewRect.RD_right = 430;
    snapshot(&sources); assert(imageSourceState.viewportWidth == 400 && viewQueries == 1);
    viewRect.RD_left = -2147483647 - 1; viewRect.RD_right = 2147483647;
    snapshot(&sources); assert(imageSourceState.viewportWidth == 65535);
    viewRect.RD_right = viewRect.RD_left;
    snapshot(&sources); assert(!imageSourceState.viewportWidth);
    viewRect.RD_left = 10; viewRect.RD_right = 0;
    snapshot(&sources); assert(!imageSourceState.viewportWidth);
    viewRect.RD_left = 0; viewRect.RD_right = 640;
    snapshot(&sources); assert(imageSourceState.viewportWidth == 640);
    snapshot(0); assert(!imageSourceState.viewportWidth && !imageSourceState.mimeSupported);
    sources.view = 0;
    snapshot(&sources); assert(!imageSourceState.viewportWidth && viewQueries == 5);
    candidate("large 1280w, small 320w, medium 640w", "src", 400, "medium");
    candidate("large 1280w, small 320w, medium 640w", "src", 640, "medium");
    candidate("small 320w, medium 640w, large 1280w", "src", 2000, "large");
    candidate("large 1280w, small 320w", "src", 0, "small");
    candidate("first 640w, second 640w", 0, 640, "first");
    candidate("  bare?width=640\t", "src", 640, "bare?width=640");
    candidate("bad 0w, bad -1w, bad 4294967296w, bad 12ww", 0, 640, 0);
    candidate("huge 4294967295w, small 640w", 0, 65535, "huge");
    candidate("density .5x, width 640w", "src", 400, "width");
    candidate("two 2x, low .75x", "src", 400, "low");
    candidate("two 2x", "src", 400, "src");
    candidate("two 2x, one 1x", "src", 400, "one");
    candidate("bad 1.x, bad 0x", 0, 400, 0);
    candidate("low .5e0x, two 2x", 0, 400, "low");
    assert(PictureMediaMatches(0, 0) && PictureMediaMatches("", 0));
    assert(PictureMediaMatches(" ( MAX-width : 420 PX ) \t", 420));
    assert(!PictureMediaMatches("(max-width:420px)", 421));
    assert(PictureMediaMatches("(min-width:1024px)", 1024));
    assert(!PictureMediaMatches("(min-width:1024px)", 1023));
    assert(!PictureMediaMatches("(max-width:420px)", 0));
    assert(!PictureMediaMatches("(min-width:4294967296px)", 400));
    assert(PictureMediaMatches("(max-width:4294967295px)", 400));
    assert(!PictureMediaMatches("(max-width:4px) junk", 400));
    assert(!PictureMediaMatches("(max-width:4px) and (min-width:0px)", 400));
    assert(!PictureMediaMatches("(width:400px)", 400));
    assert(!PictureMediaMatches("(max-width:-1px)", 400));
    assert(!PictureMediaMatches("(", 400));
    assert(!PictureMediaMatches("(max-width", 400));
    assert(!PictureMediaMatches("(max-width:", 400));
    assert(!PictureMediaMatches("(max-width:4p", 400));
    assert(!PictureMediaMatches("(max-width:4px", 400));
    assert(FrameImageMimeSupported(" Image/JPEG \t"));
    assert(FrameImageMimeSupported("image/png"));
    assert(FrameImageMimeSupported("image/gif"));
    assert(FrameImageMimeSupported("image/svg+xml"));
    assert(!FrameImageMimeSupported("image/webp"));
    assert(!FrameImageMimeSupported("text/plain"));
    assert(!FrameImageMimeSupported("image/jpeg; charset=x"));
    memset(mimeLong, 'x', sizeof(mimeLong)); mimeLong[139] = 0;
    assert(!FrameImageMimeSupported(mimeLong));
    imageSourceState.mimeSupported = FrameImageMimeSupported;
    Open_PICTURE(&arg); Open_SOURCE(&arg);
    token = imageSourceState.pictureSource;
    assert(token && refs[token] == 1 && !G_imageCount);
    strcpy(transientURL, "changed");
    PictureBeforeTag("!", TRUE); PictureText(" \t\r\n");
    assert(imageSourceState.pictureSource == token);
    image(fallback, "selected"); assert(!refs[token]);
    Open_PICTURE(&arg); Open_SOURCE(&arg);
    currentFlags = TAG_FLUSH_TEXT;
    assert(ParseImage(fallback, CA_NULL_ELEMENT, TRUE, FALSE) == CA_NULL_ELEMENT);
    assert(!imageSourceState.inPicture && !imageSourceState.pictureSource);
    currentFlags = 0; checkLeaks();
    Open_PICTURE(&arg); Open_SOURCE(&arg);
    G_imageLimit = G_imageCount;
    assert(ParseImage(fallback, CA_NULL_ELEMENT, TRUE, FALSE) == CA_NULL_ELEMENT);
    assert(!imageSourceState.inPicture && !imageSourceState.pictureSource);
    G_imageLimit = 200; checkLeaks();
    Open_PICTURE(&arg); Open_SOURCE(&arg);
    token = imageSourceState.pictureSource;
    assert(ParseImage(fallback, 0, FALSE, FALSE) != CA_NULL_ELEMENT);
    assert(imageSourceState.pictureSource == token); releaseImage();
    assert(ParseImage(fallback, CA_NULL_ELEMENT, TRUE, TRUE) != CA_NULL_ELEMENT);
    assert(imageSourceState.pictureSource == token); releaseImage();
    ClearPicture(); assert(!refs[token]); checkLeaks();
    imageSourceState.mimeSupported = 0;
    arg.paramArray = typed;
    Open_PICTURE(&arg); Open_SOURCE(&arg);
    assert(!imageSourceState.pictureSource); checkLeaks();
    arg.paramArray = offered;
    Open_PICTURE(&arg); Open_SOURCE(&arg);
    arg.paramArray = aligned; arg.spec = SPEC_IMG;
    tableDepth = HTML_MAXTABLE;
    Open_IMG(&arg);
    assert(!strcmp(names[captured.imageURL], "changed"));
    assert(!imageSourceState.inPicture && !imageSourceState.pictureSource);
    assert(tableDepth == HTML_MAXTABLE);
    tableDepth = 0; releaseImage(); checkLeaks();
    /* Source ordering and breakpoints from tagesschau.de's top teaser. */
    imageSourceState.mimeSupported = FrameImageMimeSupported;
    for(webp = 0; webp < 2; webp++) {
        supportWebp = webp;
        for(i = 0; i < 5; i++) {
            imageSourceState.viewportWidth = widths[i];
            Open_PICTURE(&arg);
            for(j = 0; j < 8; j++) {
                arg.paramArray = news[j];
                Open_SOURCE(&arg);
            }
            image(newsImage, expected[webp][i]);
            checkLeaks();
        }
    }
}
'''


class Fixture(HTMLParser):
    def __init__(self, width, webp):
        super().__init__()
        self.width, self.webp, self.code = width, webp, []

    def handle_starttag(self, tag, attrs):
        self.code.append(f'PictureBeforeTag({json.dumps(tag.upper())}, TRUE);')
        if tag not in ("picture", "source", "img"):
            return
        attrs = dict(attrs)
        pairs = [(key.upper(), value or "") for key, value in attrs.items() if not key.startswith("data-")]
        params = ", ".join("{" + json.dumps(k) + ", " + json.dumps(v) + "}" for k, v in pairs)
        self.code.append("{ Param p[] = {" + (params + ", " if params else "") + "{0, 0}};")
        if tag != "img":
            self.code.append("TagOpenArguments arg; arg.paramArray = p;")
        if tag == "picture":
            self.code.append("Open_PICTURE(&arg);")
        elif tag == "source":
            self.code.append("Open_SOURCE(&arg);")
        elif tag == "img":
            expected = attrs.get(f"data-jpeg-{self.width}") if not self.webp else None
            expected = expected or attrs.get(f"data-expect-{self.width}") or attrs.get("data-expect")
            assert expected
            assert (root / "htmtest" / expected).is_file(), expected
            self.code.append("image(p, " + json.dumps(expected) + ");")
        self.code.append("}")

    def handle_endtag(self, tag):
        self.code.append(f'PictureBeforeTag({json.dumps(tag.upper())}, FALSE);')
        if tag == "picture":
            self.code.append("ClearPicture();")

    def handle_data(self, data):
        self.code.append("PictureText(" + json.dumps(data) + ");")


fixture = "".join((root / "htmtest" / name).read_text() for name in ("srcset.htm", "picture.htm"))
for width in (0, 400, 640, 800):
    for webp in (0, 1):
        parsed = Fixture(width, webp)
        parsed.feed(fixture)
        harness += f"static void fixture{width}_{webp}(void)\n{{\n"
        harness += f"imageSourceState.viewportWidth = {width}; supportWebp = {webp};\n"
        harness += "imageSourceState.mimeSupported = FrameImageMimeSupported;\n"
        harness += "\n".join(parsed.code) + "\ncheckLeaks();\n}\n"
harness += "int main(void) { fitChecks(); unitChecks();\n"
harness += "\n".join(f"fixture{width}_{webp}();" for width in (0, 400, 640, 800) for webp in (0, 1))
harness += '\nputs("image-source checks passed"); return 0; }\n'

# Check hooks that cannot run without GEOS object/VM infrastructure.
tags = (root / "htmlpars/parstags.goc").read_bytes().decode("latin1")
assert "PictureBeforeTag(tag, openTag)" in function(parser, "HandleTag")
assert "PictureText(buf)" in core and "ClearPicture();" in core[:core.index("FinishTransferItem();")]
assert "ClearPicture();" in core[core.index("cleanupExit:"):]
assert "PictureBeforeTag" not in function(tags, "OpenTag")
assert "if(spec == SPEC_PICTURE)\n        ClearPicture();" in function(tags, "CloseTag")
assert "ParseEvents(arg->paramArray, HTML_EVENT_OBJECT_IMAGE, image)" in function(source, "Open_IMG")
replacement = (root.parents[2] / "Appl/Breadbox/BbxBrow/urltext/URLTEXT.goc").read_bytes().decode("latin1")
assert "HTML_IDF_INLINE_SVG | HTML_IDF_PICTURE" in function(replacement, "IReplaceGraphic")
for message in ("MSG_HTML_TEXT_CLAMP_INLINE_SVG_TO_VIEWPORT", "MSG_HTML_TEXT_RESOLVE_INLINE_SVG"):
    method = display[display.index("@method HTMLTextClass, " + message):]
    method = method[:method.index("\n}")]
    assert "HTML_IDF_INLINE_SVG | HTML_IDF_PICTURE" in method
    assert "pself->HTI_pageLeftMargin" in method

with tempfile.TemporaryDirectory() as directory:
    c_file = Path(directory) / "check_image_sources.c"
    binary = Path(directory) / "check_image_sources"
    c_file.write_text(harness)
    subprocess.run(["cc", "-std=c89", "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-parameter", str(c_file), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
