/*
 * fntpatch.c
 *
 * Unpack and conservatively patch PC/GEOS BSWF bitmap font strikes.
 */

#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#define mkdir(path, mode) _mkdir(path)
#define PATH_SEP '\\'
#else
#include <unistd.h>
#define PATH_SEP '/'
#endif

#include "nimbus.h"

#define TOOL_FORMAT_VERSION 1
#define BSWF_HEADER_SIZE 41
#define POINT_ENTRY_SIZE 10
#define POINT_ENTRY_SHIFT 6
#define FONTBUF_CORE_SIZE 71
#define CHAR_TABLE_ENTRY_SIZE 8
#define CHAR_DATA_HEADER_SIZE 4

#define CHAR_NOT_EXIST 0
#define CHAR_NOT_LOADED 1
#define CHAR_NOT_BUILT 2
#define CHAR_MISSING 3

#define CTF_NO_DATA 0x08
#define FBF_IS_REGION 0x08

typedef unsigned char Byte;

typedef struct {
    Byte *dataP;
    long size;
} FileData;

typedef struct {
    unsigned long id;
    unsigned int ver;
    unsigned int hdrSize;
    unsigned int fontID;
    unsigned int rasterizer;
    unsigned int family;
    char name[21];
    unsigned int pointSizeTab;
    unsigned int pointSizeEnd;
    unsigned int outlineTab;
    unsigned int outlineEnd;
} FontHeader;

typedef struct {
    unsigned int index;
    unsigned int style;
    Byte pointSize[3];
    unsigned int dataSize;
    unsigned long filePos;
} PointEntry;

typedef struct {
    unsigned int dataSize;
    unsigned int maker;
    unsigned int kernCount;
    unsigned int kernPairPtr;
    unsigned int kernValuePtr;
    unsigned int firstChar;
    unsigned int lastChar;
    unsigned int defaultChar;
    unsigned int pixHeight;
    unsigned int flags;
    unsigned int heapCount;
    unsigned int charCount;
    unsigned int charTableOffset;
} FontBufInfo;

typedef struct {
    unsigned int charCode;
    unsigned int cteOffset;
    unsigned int dataOffset;
    unsigned int widthFrac;
    int widthInt;
    unsigned int flags;
    unsigned int usage;
    unsigned int pictureWidth;
    unsigned int numRows;
    int xoff;
    int yoff;
    unsigned int rowBytes;
    unsigned long payloadBytes;
    unsigned long dataFileOffset;
    int exportable;
    char reason[64];
} GlyphInfo;

typedef struct {
    char *dataP;
    long size;
} TextData;

static int DoUnpack(const char *fontPath, const char *fontDir);
static int DoPack(const char *fontDir, const char *outPath);

static unsigned int ReadLE16(const Byte *p)
{
    return (unsigned int)p[0] | ((unsigned int)p[1] << 8);
}

static unsigned long ReadLE32(const Byte *p)
{
    return (unsigned long)p[0] |
           ((unsigned long)p[1] << 8) |
           ((unsigned long)p[2] << 16) |
           ((unsigned long)p[3] << 24);
}

static int ReadSByte(Byte b)
{
    return (b & 0x80) ? ((int)b - 256) : (int)b;
}

static int ReadSWord(const Byte *p)
{
    unsigned int v;

    v = ReadLE16(p);
    return (v & 0x8000) ? ((int)v - 65536) : (int)v;
}

static unsigned long Checksum(const Byte *dataP, long size)
{
    unsigned long hash;
    long i;

    hash = 2166136261UL;
    for (i = 0; i < size; i++) {
        hash ^= (unsigned long)dataP[i];
        hash *= 16777619UL;
    }
    return hash;
}

static void Usage(void)
{
    fprintf(stderr, "usage: fntpatch unpack <font.fnt> <fontdir>\n");
    fprintf(stderr, "       fntpatch pack <fontdir> <out.fnt>\n");
}

static char *DupString(const char *s)
{
    char *d;

    d = (char *)malloc(strlen(s) + 1);
    if (d != (char *)0) {
        strcpy(d, s);
    }
    return d;
}

static char *PathJoin(const char *a, const char *b)
{
    char *r;
    size_t alen;
    size_t blen;
    int needSep;

    alen = strlen(a);
    blen = strlen(b);
    needSep = (alen > 0 && a[alen - 1] != '/' && a[alen - 1] != '\\');
    r = (char *)malloc(alen + blen + (needSep ? 2 : 1));
    if (r == (char *)0) {
        return (char *)0;
    }
    strcpy(r, a);
    if (needSep) {
        r[alen] = PATH_SEP;
        r[alen + 1] = '\0';
    }
    strcat(r, b);
    return r;
}

static const char *BaseName(const char *path)
{
    const char *slashP;
    const char *backP;

    slashP = strrchr(path, '/');
    backP = strrchr(path, '\\');
    if (slashP == (const char *)0 || backP > slashP) {
        slashP = backP;
    }
    return slashP == (const char *)0 ? path : slashP + 1;
}

static int EnsureDir(const char *path)
{
    struct stat st;

    if (stat(path, &st) == 0) {
        if ((st.st_mode & S_IFDIR) != 0) {
            return 1;
        }
        fprintf(stderr, "fntpatch: %s exists and is not a directory\n", path);
        return 0;
    }
    if (mkdir(path, 0777) != 0) {
        fprintf(stderr, "fntpatch: cannot create %s: %s\n",
                path, strerror(errno));
        return 0;
    }
    return 1;
}

static int FileExists(const char *path)
{
    struct stat st;

    return stat(path, &st) == 0;
}

static int CheckUnpackConflicts(const char *fontDir)
{
    char *pathP;
    int ok;

    ok = 1;
    if (FileExists(fontDir)) {
        pathP = PathJoin(fontDir, "original.fnt");
        if (pathP == (char *)0) {
            return 0;
        }
        if (FileExists(pathP)) {
            fprintf(stderr, "fntpatch: refusing to overwrite %s\n", pathP);
            ok = 0;
        }
        free(pathP);

        pathP = PathJoin(fontDir, "font.meta");
        if (pathP == (char *)0) {
            return 0;
        }
        if (FileExists(pathP)) {
            fprintf(stderr, "fntpatch: refusing to overwrite %s\n", pathP);
            ok = 0;
        }
        free(pathP);

        pathP = PathJoin(fontDir, "strikes");
        if (pathP == (char *)0) {
            return 0;
        }
        if (FileExists(pathP)) {
            fprintf(stderr, "fntpatch: refusing to overwrite %s\n", pathP);
            ok = 0;
        }
        free(pathP);
    }
    return ok;
}

static int ReadFile(const char *path, FileData *fileP)
{
    FILE *fp;
    long size;
    Byte *dataP;

    fileP->dataP = (Byte *)0;
    fileP->size = 0;
    fp = fopen(path, "rb");
    if (fp == (FILE *)0) {
        fprintf(stderr, "fntpatch: cannot open %s\n", path);
        return 0;
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return 0;
    }
    size = ftell(fp);
    if (size < 0 || fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return 0;
    }
    dataP = (Byte *)malloc((size_t)size);
    if (dataP == (Byte *)0 && size != 0) {
        fclose(fp);
        fprintf(stderr, "fntpatch: out of memory reading %s\n", path);
        return 0;
    }
    if (size != 0 && fread(dataP, 1, (size_t)size, fp) != (size_t)size) {
        free(dataP);
        fclose(fp);
        fprintf(stderr, "fntpatch: failed reading %s\n", path);
        return 0;
    }
    fclose(fp);
    fileP->dataP = dataP;
    fileP->size = size;
    return 1;
}

static int WriteFile(const char *path, const Byte *dataP, long size)
{
    FILE *fp;

    fp = fopen(path, "wb");
    if (fp == (FILE *)0) {
        fprintf(stderr, "fntpatch: cannot write %s\n", path);
        return 0;
    }
    if (size != 0 && fwrite(dataP, 1, (size_t)size, fp) != (size_t)size) {
        fclose(fp);
        fprintf(stderr, "fntpatch: failed writing %s\n", path);
        return 0;
    }
    if (fclose(fp) != 0) {
        fprintf(stderr, "fntpatch: failed closing %s\n", path);
        return 0;
    }
    return 1;
}

static int ReadTextFile(const char *path, TextData *textP)
{
    FileData file;
    char *dataP;

    if (!ReadFile(path, &file)) {
        return 0;
    }
    dataP = (char *)malloc((size_t)file.size + 1);
    if (dataP == (char *)0) {
        free(file.dataP);
        return 0;
    }
    if (file.size != 0) {
        memcpy(dataP, file.dataP, (size_t)file.size);
    }
    dataP[file.size] = '\0';
    free(file.dataP);
    textP->dataP = dataP;
    textP->size = file.size;
    return 1;
}

static int ParseHeader(const FileData *fileP, FontHeader *hdrP)
{
    const Byte *p;

    if (fileP->size < BSWF_HEADER_SIZE) {
        fprintf(stderr, "fntpatch: file is too small for a BSWF header\n");
        return 0;
    }
    p = fileP->dataP;
    hdrP->id = ReadLE32(p);
    if (hdrP->id != BSWF_ID) {
        fprintf(stderr, "fntpatch: not a BSWF font\n");
        return 0;
    }
    hdrP->ver = ReadLE16(p + 4);
    hdrP->hdrSize = ReadLE16(p + 6);
    hdrP->fontID = ReadLE16(p + 8);
    hdrP->rasterizer = ReadLE16(p + 10);
    hdrP->family = p[12];
    memcpy(hdrP->name, p + 13, 20);
    hdrP->name[20] = '\0';
    hdrP->pointSizeTab = ReadLE16(p + 33);
    hdrP->pointSizeEnd = ReadLE16(p + 35);
    hdrP->outlineTab = ReadLE16(p + 37);
    hdrP->outlineEnd = ReadLE16(p + 39);
    return 1;
}

static void CleanAscii(char *s)
{
    unsigned char c;

    while (*s != '\0') {
        c = (unsigned char)*s;
        if (c < 32 || c > 126) {
            *s = '_';
        }
        s++;
    }
}

static int LoadPointEntries(const FileData *fileP, const FontHeader *hdrP,
                            PointEntry **entriesPP, unsigned int *countP)
{
    PointEntry *entriesP;
    unsigned int count;
    unsigned int i;
    unsigned long tableStart;
    unsigned long tableEnd;
    unsigned long entryPos;
    const Byte *p;

    *entriesPP = (PointEntry *)0;
    *countP = 0;
    if (hdrP->pointSizeTab == 0 && hdrP->pointSizeEnd == 0) {
        return 1;
    }
    if (hdrP->pointSizeEnd < hdrP->pointSizeTab ||
        ((hdrP->pointSizeEnd - hdrP->pointSizeTab) % POINT_ENTRY_SIZE) != 0) {
        fprintf(stderr, "fntpatch: invalid point-size table bounds\n");
        return 0;
    }
    tableStart = hdrP->pointSizeTab;
    tableEnd = hdrP->pointSizeEnd;
    if (tableEnd + POINT_ENTRY_SHIFT > (unsigned long)fileP->size) {
        fprintf(stderr, "fntpatch: point-size table extends past EOF\n");
        return 0;
    }
    count = (unsigned int)((tableEnd - tableStart) / POINT_ENTRY_SIZE);
    entriesP = (PointEntry *)calloc(count == 0 ? 1 : count,
                                    sizeof(PointEntry));
    if (entriesP == (PointEntry *)0) {
        return 0;
    }
    for (i = 0; i < count; i++) {
        entryPos = tableStart + POINT_ENTRY_SHIFT + i * POINT_ENTRY_SIZE;
        if (entryPos + POINT_ENTRY_SIZE > (unsigned long)fileP->size) {
            free(entriesP);
            fprintf(stderr, "fntpatch: point-size entry extends past EOF\n");
            return 0;
        }
        p = fileP->dataP + entryPos;
        entriesP[i].index = i;
        entriesP[i].style = p[0];
        entriesP[i].pointSize[0] = p[1];
        entriesP[i].pointSize[1] = p[2];
        entriesP[i].pointSize[2] = p[3];
        entriesP[i].dataSize = ReadLE16(p + 4);
        entriesP[i].filePos = ReadLE32(p + 6);
        if (entriesP[i].filePos + entriesP[i].dataSize >
            (unsigned long)fileP->size) {
            free(entriesP);
            fprintf(stderr, "fntpatch: strike %u extends past EOF\n", i);
            return 0;
        }
    }
    *entriesPP = entriesP;
    *countP = count;
    return 1;
}

static int ParseFontBuf(const Byte *strikeP, unsigned int strikeSize,
                        FontBufInfo *fbP)
{
    if (strikeSize < FONTBUF_CORE_SIZE) {
        return 0;
    }
    fbP->dataSize = ReadLE16(strikeP + 0);
    fbP->maker = ReadLE16(strikeP + 2);
    fbP->kernCount = ReadLE16(strikeP + 34);
    fbP->kernPairPtr = ReadLE16(strikeP + 36);
    fbP->kernValuePtr = ReadLE16(strikeP + 38);
    fbP->firstChar = strikeP[40];
    fbP->lastChar = strikeP[41];
    fbP->defaultChar = strikeP[42];
    fbP->pixHeight = ReadLE16(strikeP + 66);
    fbP->flags = strikeP[68];
    fbP->heapCount = ReadLE16(strikeP + 69);
    if (fbP->lastChar < fbP->firstChar) {
        return 0;
    }
    fbP->charCount = fbP->lastChar - fbP->firstChar + 1;
    if (fbP->dataSize == 0 || fbP->dataSize > strikeSize) {
        fbP->dataSize = strikeSize;
    }
    if (fbP->charCount > 256 ||
        fbP->charCount * CHAR_TABLE_ENTRY_SIZE > fbP->dataSize) {
        return 0;
    }
    return 1;
}

static int ScoreCharTable(const Byte *strikeP, unsigned int size,
                          unsigned int offset, unsigned int count)
{
    int score;
    unsigned int i;
    unsigned int entry;
    unsigned int dataOffset;
    unsigned int flags;
    unsigned int width;
    unsigned int height;
    unsigned long rowBytes;
    unsigned long payload;

    if (offset + count * CHAR_TABLE_ENTRY_SIZE > size) {
        return -100000;
    }
    score = 0;
    for (i = 0; i < count; i++) {
        entry = offset + i * CHAR_TABLE_ENTRY_SIZE;
        dataOffset = ReadLE16(strikeP + entry);
        flags = strikeP[entry + 5];
        if ((flags & CTF_NO_DATA) != 0 || dataOffset <= CHAR_MISSING) {
            score += 2;
            continue;
        }
        if (dataOffset + CHAR_DATA_HEADER_SIZE > size) {
            score -= 8;
            continue;
        }
        width = strikeP[dataOffset];
        height = strikeP[dataOffset + 1];
        rowBytes = (width + 7) / 8;
        payload = rowBytes * height;
        if (dataOffset + CHAR_DATA_HEADER_SIZE + payload <= size) {
            score += 3;
            if (height <= 128 && width <= 128) {
                score += 1;
            }
        } else {
            score -= 8;
        }
    }
    return score;
}

static int FindCharTable(const Byte *strikeP, FontBufInfo *fbP)
{
    unsigned int offset;
    unsigned int limit;
    unsigned int bestOffset;
    int score;
    int bestScore;

    if (fbP->charCount == 0 ||
        fbP->dataSize < fbP->charCount * CHAR_TABLE_ENTRY_SIZE) {
        return 0;
    }
    limit = fbP->dataSize - fbP->charCount * CHAR_TABLE_ENTRY_SIZE;
    bestOffset = FONTBUF_CORE_SIZE;
    bestScore = -100000;
    for (offset = FONTBUF_CORE_SIZE; offset <= limit; offset++) {
        score = ScoreCharTable(strikeP, fbP->dataSize, offset,
                               fbP->charCount);
        if (score > bestScore) {
            bestScore = score;
            bestOffset = offset;
        }
    }
    if (bestScore < (int)fbP->charCount) {
        return 0;
    }
    fbP->charTableOffset = bestOffset;
    return 1;
}

static void AnalyzeGlyph(const Byte *strikeP, const FontBufInfo *fbP,
                         unsigned int i, unsigned long strikeFileOffset,
                         GlyphInfo *glyphP)
{
    unsigned int entry;
    unsigned int dataOffset;
    unsigned int width;
    unsigned int height;
    unsigned long rowBytes;
    unsigned long payload;

    memset(glyphP, 0, sizeof(*glyphP));
    entry = fbP->charTableOffset + i * CHAR_TABLE_ENTRY_SIZE;
    dataOffset = ReadLE16(strikeP + entry);
    glyphP->charCode = fbP->firstChar + i;
    glyphP->cteOffset = entry;
    glyphP->dataOffset = dataOffset;
    glyphP->widthFrac = strikeP[entry + 2];
    glyphP->widthInt = ReadSWord(strikeP + entry + 3);
    glyphP->flags = strikeP[entry + 5];
    glyphP->usage = ReadLE16(strikeP + entry + 6);
    glyphP->exportable = 0;

    if ((glyphP->flags & CTF_NO_DATA) != 0) {
        strcpy(glyphP->reason, "ctf_no_data");
        return;
    }
    if (dataOffset <= CHAR_MISSING) {
        strcpy(glyphP->reason, "missing_sentinel");
        return;
    }
    if (dataOffset + CHAR_DATA_HEADER_SIZE > fbP->dataSize) {
        strcpy(glyphP->reason, "data_header_out_of_range");
        return;
    }
    width = strikeP[dataOffset];
    height = strikeP[dataOffset + 1];
    rowBytes = (width + 7) / 8;
    payload = rowBytes * height;
    if (dataOffset + CHAR_DATA_HEADER_SIZE + payload > fbP->dataSize) {
        strcpy(glyphP->reason, "payload_out_of_range");
        return;
    }
    glyphP->pictureWidth = width;
    glyphP->numRows = height;
    glyphP->yoff = ReadSByte(strikeP[dataOffset + 2]);
    glyphP->xoff = ReadSByte(strikeP[dataOffset + 3]);
    glyphP->rowBytes = (unsigned int)rowBytes;
    glyphP->payloadBytes = payload;
    glyphP->dataFileOffset = strikeFileOffset + dataOffset +
                             CHAR_DATA_HEADER_SIZE;
    glyphP->exportable = 1;
    strcpy(glyphP->reason, "ok");
}

static const char *GeosCharName(unsigned int charCode)
{
    switch (charCode) {
    case 0x00: return "C_NULL";
    case 0x09: return "C_TAB";
    case 0x0a: return "C_LINEFEED";
    case 0x0d: return "C_ENTER";
    case 0x1b: return "C_THINSPACE";
    case 0x1c: return "C_ENSPACE";
    case 0x1d: return "C_EMSPACE";
    case 0x1e: return "C_NONBRKHYPHEN";
    case 0x1f: return "C_OPTHYPHEN";
    case 0x20: return "C_SPACE";
    case 0x21: return "C_EXCLAMATION";
    case 0x22: return "C_QUOTE";
    case 0x23: return "C_NUMBER_SIGN";
    case 0x24: return "C_DOLLAR_SIGN";
    case 0x25: return "C_PERCENT";
    case 0x26: return "C_AMPERSAND";
    case 0x27: return "C_SNG_QUOTE";
    case 0x28: return "C_LEFT_PAREN";
    case 0x29: return "C_RIGHT_PAREN";
    case 0x2a: return "C_ASTERISK";
    case 0x2b: return "C_PLUS";
    case 0x2c: return "C_COMMA";
    case 0x2d: return "C_MINUS";
    case 0x2e: return "C_PERIOD";
    case 0x2f: return "C_SLASH";
    case 0x30: return "C_ZERO";
    case 0x31: return "C_ONE";
    case 0x32: return "C_TWO";
    case 0x33: return "C_THREE";
    case 0x34: return "C_FOUR";
    case 0x35: return "C_FIVE";
    case 0x36: return "C_SIX";
    case 0x37: return "C_SEVEN";
    case 0x38: return "C_EIGHT";
    case 0x39: return "C_NINE";
    case 0x3a: return "C_COLON";
    case 0x3b: return "C_SEMICOLON";
    case 0x3c: return "C_LESS_THAN";
    case 0x3d: return "C_EQUAL";
    case 0x3e: return "C_GREATER_THAN";
    case 0x3f: return "C_QUESTION_MARK";
    case 0x40: return "C_AT_SIGN";
    case 0x41: return "C_CAP_A";
    case 0x42: return "C_CAP_B";
    case 0x43: return "C_CAP_C";
    case 0x44: return "C_CAP_D";
    case 0x45: return "C_CAP_E";
    case 0x46: return "C_CAP_F";
    case 0x47: return "C_CAP_G";
    case 0x48: return "C_CAP_H";
    case 0x49: return "C_CAP_I";
    case 0x4a: return "C_CAP_J";
    case 0x4b: return "C_CAP_K";
    case 0x4c: return "C_CAP_L";
    case 0x4d: return "C_CAP_M";
    case 0x4e: return "C_CAP_N";
    case 0x4f: return "C_CAP_O";
    case 0x50: return "C_CAP_P";
    case 0x51: return "C_CAP_Q";
    case 0x52: return "C_CAP_R";
    case 0x53: return "C_CAP_S";
    case 0x54: return "C_CAP_T";
    case 0x55: return "C_CAP_U";
    case 0x56: return "C_CAP_V";
    case 0x57: return "C_CAP_W";
    case 0x58: return "C_CAP_X";
    case 0x59: return "C_CAP_Y";
    case 0x5a: return "C_CAP_Z";
    case 0x5b: return "C_LEFT_BRACKET";
    case 0x5c: return "C_BACKSLASH";
    case 0x5d: return "C_RIGHT_BRACKET";
    case 0x5e: return "C_ASCII_CIRCUMFLEX";
    case 0x5f: return "C_UNDERSCORE";
    case 0x60: return "C_BACKQUOTE";
    case 0x61: return "C_SMALL_A";
    case 0x62: return "C_SMALL_B";
    case 0x63: return "C_SMALL_C";
    case 0x64: return "C_SMALL_D";
    case 0x65: return "C_SMALL_E";
    case 0x66: return "C_SMALL_F";
    case 0x67: return "C_SMALL_G";
    case 0x68: return "C_SMALL_H";
    case 0x69: return "C_SMALL_I";
    case 0x6a: return "C_SMALL_J";
    case 0x6b: return "C_SMALL_K";
    case 0x6c: return "C_SMALL_L";
    case 0x6d: return "C_SMALL_M";
    case 0x6e: return "C_SMALL_N";
    case 0x6f: return "C_SMALL_O";
    case 0x70: return "C_SMALL_P";
    case 0x71: return "C_SMALL_Q";
    case 0x72: return "C_SMALL_R";
    case 0x73: return "C_SMALL_S";
    case 0x74: return "C_SMALL_T";
    case 0x75: return "C_SMALL_U";
    case 0x76: return "C_SMALL_V";
    case 0x77: return "C_SMALL_W";
    case 0x78: return "C_SMALL_X";
    case 0x79: return "C_SMALL_Y";
    case 0x7a: return "C_SMALL_Z";
    case 0x7b: return "C_LEFT_BRACE";
    case 0x7c: return "C_VERTICAL_BAR";
    case 0x7d: return "C_RIGHT_BRACE";
    case 0x7e: return "C_ASCII_TILDE";
    case 0x7f: return "C_DELETE";
    case 0x80: return "C_UA_DIERESIS";
    case 0x81: return "C_UA_RING";
    case 0x82: return "C_UC_CEDILLA";
    case 0x83: return "C_UE_ACUTE";
    case 0x84: return "C_UN_TILDE";
    case 0x85: return "C_UO_DIERESIS";
    case 0x86: return "C_UU_DIERESIS";
    case 0x87: return "C_LA_ACUTE";
    case 0x88: return "C_LA_GRAVE";
    case 0x89: return "C_LA_CIRCUMFLEX";
    case 0x8a: return "C_LA_DIERESIS";
    case 0x8b: return "C_LA_TILDE";
    case 0x8c: return "C_LA_RING";
    case 0x8d: return "C_LC_CEDILLA";
    case 0x8e: return "C_LE_ACUTE";
    case 0x8f: return "C_LE_GRAVE";
    case 0x90: return "C_LE_CIRCUMFLEX";
    case 0x91: return "C_LE_DIERESIS";
    case 0x92: return "C_LI_ACUTE";
    case 0x93: return "C_LI_GRAVE";
    case 0x94: return "C_LI_CIRCUMFLEX";
    case 0x95: return "C_LI_DIERESIS";
    case 0x96: return "C_LN_TILDE";
    case 0x97: return "C_LO_ACUTE";
    case 0x98: return "C_LO_GRAVE";
    case 0x99: return "C_LO_CIRCUMFLEX";
    case 0x9a: return "C_LO_DIERESIS";
    case 0x9b: return "C_LO_TILDE";
    case 0x9c: return "C_LU_ACUTE";
    case 0x9d: return "C_LU_GRAVE";
    case 0x9e: return "C_LU_CIRCUMFLEX";
    case 0x9f: return "C_LU_DIERESIS";
    case 0xa0: return "C_DAGGER";
    case 0xa1: return "C_DEGREE";
    case 0xa2: return "C_CENT";
    case 0xa3: return "C_STERLING";
    case 0xa4: return "C_SECTION";
    case 0xa5: return "C_BULLET";
    case 0xa6: return "C_PARAGRAPH";
    case 0xa7: return "C_GERMANDBLS";
    case 0xa8: return "C_REGISTERED";
    case 0xa9: return "C_COPYRIGHT";
    case 0xaa: return "C_TRADEMARK";
    case 0xab: return "C_ACUTE";
    case 0xac: return "C_DIERESIS";
    case 0xad: return "C_NOTEQUAL";
    case 0xae: return "C_U_AE";
    case 0xaf: return "C_UO_SLASH";
    case 0xb0: return "C_INFINITY";
    case 0xb1: return "C_PLUSMINUS";
    case 0xb2: return "C_LESSEQUAL";
    case 0xb3: return "C_GREATEREQUAL";
    case 0xb4: return "C_YEN";
    case 0xb5: return "C_L_MU";
    case 0xb6: return "C_L_DELTA";
    case 0xb7: return "C_U_SIGMA";
    case 0xb8: return "C_U_PI";
    case 0xb9: return "C_L_PI";
    case 0xba: return "C_INTEGRAL";
    case 0xbb: return "C_ORDFEMININE";
    case 0xbc: return "C_ORDMASCULINE";
    case 0xbd: return "C_U_OMEGA";
    case 0xbe: return "C_L_AE";
    case 0xbf: return "C_LO_SLASH";
    case 0xc0: return "C_QUESTIONDOWN";
    case 0xc1: return "C_EXCLAMDOWN";
    case 0xc2: return "C_LOGICAL_NOT";
    case 0xc3: return "C_ROOT";
    case 0xc4: return "C_FLORIN";
    case 0xc5: return "C_APPROX_EQUAL";
    case 0xc6: return "C_U_DELTA";
    case 0xc7: return "C_GUILLEDBLLEFT";
    case 0xc8: return "C_GUILLEDBLRIGHT";
    case 0xc9: return "C_ELLIPSIS";
    case 0xca: return "C_NONBRKSPACE";
    case 0xcb: return "C_UA_GRAVE";
    case 0xcc: return "C_UA_TILDE";
    case 0xcd: return "C_UO_TILDE";
    case 0xce: return "C_U_OE";
    case 0xcf: return "C_L_OE";
    case 0xd0: return "C_ENDASH";
    case 0xd1: return "C_EMDASH";
    case 0xd2: return "C_QUOTEDBLLEFT";
    case 0xd3: return "C_QUOTEDBLRIGHT";
    case 0xd4: return "C_QUOTESNGLEFT";
    case 0xd5: return "C_QUOTESNGRIGHT";
    case 0xd6: return "C_DIVISION";
    case 0xd7: return "C_DIAMONDBULLET";
    case 0xd8: return "C_LY_DIERESIS";
    case 0xd9: return "C_UY_DIERESIS";
    case 0xda: return "C_FRACTION";
    case 0xdb: return "C_CURRENCY";
    case 0xdc: return "C_GUILSNGLEFT";
    case 0xdd: return "C_GUILSNGRIGHT";
    case 0xde: return "C_LY_ACUTE";
    case 0xdf: return "C_UY_ACUTE";
    case 0xe0: return "C_DBLDAGGER";
    case 0xe1: return "C_CNTR_DOT";
    case 0xe2: return "C_SNGQUOTELOW";
    case 0xe3: return "C_DBLQUOTELOW";
    case 0xe4: return "C_PERTHOUSAND";
    case 0xe5: return "C_UA_CIRCUMFLEX";
    case 0xe6: return "C_UE_CIRCUMFLEX";
    case 0xe7: return "C_UA_ACUTE";
    case 0xe8: return "C_UE_DIERESIS";
    case 0xe9: return "C_UE_GRAVE";
    case 0xea: return "C_UI_ACUTE";
    case 0xeb: return "C_UI_CIRCUMFLEX";
    case 0xec: return "C_UI_DIERESIS";
    case 0xed: return "C_UI_GRAVE";
    case 0xee: return "C_UO_ACUTE";
    case 0xef: return "C_UO_CIRCUMFLEX";
    case 0xf0: return "C_LOGO";
    case 0xf1: return "C_UO_GRAVE";
    case 0xf2: return "C_UU_ACUTE";
    case 0xf3: return "C_UU_CIRCUMFLEX";
    case 0xf4: return "C_UU_GRAVE";
    case 0xf5: return "C_LI_DOTLESS";
    case 0xf6: return "C_CIRCUMFLEX";
    case 0xf7: return "C_TILDE";
    case 0xf8: return "C_MACRON";
    case 0xf9: return "C_BREVE";
    case 0xfa: return "C_DOTACCENT";
    case 0xfb: return "C_RING";
    case 0xfc: return "C_CEDILLA";
    case 0xfd: return "C_HUNGARUMLAUT";
    case 0xfe: return "C_OGONEK";
    case 0xff: return "C_CARON";
    default: return (const char *)0;
    }
}

static void FormatGlyphPBMPath(char *buf, unsigned int charCode)
{
    const char *nameP;

    nameP = GeosCharName(charCode);
    if (nameP != (const char *)0) {
        sprintf(buf, "glyphs/ch-%02x_%s.pbm", charCode, nameP);
    } else {
        sprintf(buf, "glyphs/ch-%02x.pbm", charCode);
    }
}

static int WritePBM(const char *path, const Byte *payloadP,
                    unsigned int width, unsigned int height,
                    unsigned int rowBytes)
{
    FILE *fp;
    unsigned int row;
    unsigned int col;
    unsigned int bit;

    fp = fopen(path, "w");
    if (fp == (FILE *)0) {
        fprintf(stderr, "fntpatch: cannot write %s\n", path);
        return 0;
    }
    fprintf(fp, "P1\n%u %u\n", width, height);
    for (row = 0; row < height; row++) {
        for (col = 0; col < width; col++) {
            bit = (payloadP[row * rowBytes + col / 8] >>
                   (7 - (col % 8))) & 1;
            fprintf(fp, "%u", bit);
            if (col + 1 < width) {
                fputc(' ', fp);
            }
        }
        fputc('\n', fp);
    }
    if (fclose(fp) != 0) {
        fprintf(stderr, "fntpatch: failed closing %s\n", path);
        return 0;
    }
    return 1;
}

static int WriteFontMeta(const char *path, const char *sourcePath,
                         const FontHeader *hdrP, const FileData *fileP,
                         unsigned int count, char **strikeNamesP)
{
    FILE *fp;
    unsigned int i;
    char fontName[21];

    fp = fopen(path, "w");
    if (fp == (FILE *)0) {
        fprintf(stderr, "fntpatch: cannot write %s\n", path);
        return 0;
    }
    strcpy(fontName, hdrP->name);
    CleanAscii(fontName);
    fprintf(fp, "checksum=0x%08lx\n", Checksum(fileP->dataP, fileP->size));
    fprintf(fp, "font_file_size=%ld\n", fileP->size);
    fprintf(fp, "font_name=%s\n", fontName);
    fprintf(fp, "header.family=0x%02x\n", hdrP->family);
    fprintf(fp, "header.fontID=0x%04x\n", hdrP->fontID);
    fprintf(fp, "header.hdrSize=%u\n", hdrP->hdrSize);
    fprintf(fp, "header.id=0x%08lx\n", hdrP->id);
    fprintf(fp, "header.outlineEnd=%u\n", hdrP->outlineEnd);
    fprintf(fp, "header.outlineTab=%u\n", hdrP->outlineTab);
    fprintf(fp, "header.pointSizeEnd=%u\n", hdrP->pointSizeEnd);
    fprintf(fp, "header.pointSizeTab=%u\n", hdrP->pointSizeTab);
    fprintf(fp, "header.rasterizer=0x%04x\n", hdrP->rasterizer);
    fprintf(fp, "header.ver=0x%04x\n", hdrP->ver);
    fprintf(fp, "point_size_count=%u\n", count);
    fprintf(fp, "source_filename=%s\n", BaseName(sourcePath));
    for (i = 0; i < count; i++) {
        fprintf(fp, "strike.%03u.dir=%s\n", i, strikeNamesP[i]);
    }
    fprintf(fp, "tool_format_version=%u\n", TOOL_FORMAT_VERSION);
    if (fclose(fp) != 0) {
        fprintf(stderr, "fntpatch: failed closing %s\n", path);
        return 0;
    }
    return 1;
}

static void FormatPointSize(const PointEntry *entryP, char *buf)
{
    sprintf(buf, "%02x%02x.%02x",
            entryP->pointSize[0], entryP->pointSize[1],
            entryP->pointSize[2]);
}

static int WriteStrikeMeta(const char *path, const PointEntry *entryP,
                           const FontBufInfo *fbP)
{
    FILE *fp;
    char pointBuf[16];

    fp = fopen(path, "w");
    if (fp == (FILE *)0) {
        fprintf(stderr, "fntpatch: cannot write %s\n", path);
        return 0;
    }
    FormatPointSize(entryP, pointBuf);
    fprintf(fp, "char_count=%u\n", fbP->charCount);
    fprintf(fp, "char_table_offset=%u\n", fbP->charTableOffset);
    fprintf(fp, "fb_data_size=%u\n", fbP->dataSize);
    fprintf(fp, "fb_defaultChar=%u\n", fbP->defaultChar);
    fprintf(fp, "fb_firstChar=%u\n", fbP->firstChar);
    fprintf(fp, "fb_flags=0x%02x\n", fbP->flags);
    fprintf(fp, "fb_heapCount=%u\n", fbP->heapCount);
    fprintf(fp, "fb_kernCount=%u\n", fbP->kernCount);
    fprintf(fp, "fb_kernPairPtr=%u\n", fbP->kernPairPtr);
    fprintf(fp, "fb_kernValuePtr=%u\n", fbP->kernValuePtr);
    fprintf(fp, "fb_lastChar=%u\n", fbP->lastChar);
    fprintf(fp, "fb_maker=0x%04x\n", fbP->maker);
    fprintf(fp, "fb_pixHeight=%u\n", fbP->pixHeight);
    fprintf(fp, "point_size=%s\n", pointBuf);
    fprintf(fp, "point_size_bytes=%02x%02x%02x\n",
            entryP->pointSize[0], entryP->pointSize[1],
            entryP->pointSize[2]);
    fprintf(fp, "point_size_entry_index=%u\n", entryP->index);
    fprintf(fp, "pse_dataSize=%u\n", entryP->dataSize);
    fprintf(fp, "pse_filePos=%lu\n", entryP->filePos);
    fprintf(fp, "pse_style=0x%02x\n", entryP->style);
    if (fclose(fp) != 0) {
        fprintf(stderr, "fntpatch: failed closing %s\n", path);
        return 0;
    }
    return 1;
}

static int ExportStrike(const char *strikeDir, const char *glyphDir,
                        const Byte *fileDataP, const PointEntry *entryP,
                        unsigned int *glyphsExportedP)
{
    const Byte *strikeP;
    FontBufInfo fb;
    GlyphInfo glyph;
    FILE *metaFp;
    char *pathP;
    char fileName[96];
    const char *charNameP;
    unsigned int i;
    unsigned int exported;

    (void)glyphDir;

    strikeP = fileDataP + entryP->filePos;
    if (!ParseFontBuf(strikeP, entryP->dataSize, &fb) ||
        !FindCharTable(strikeP, &fb)) {
        fprintf(stderr, "fntpatch: cannot interpret strike %u as FontBuf\n",
                entryP->index);
        return 0;
    }
    if ((fb.flags & FBF_IS_REGION) != 0) {
        fprintf(stderr, "fntpatch: strike %u contains region glyphs\n",
                entryP->index);
        return 0;
    }
    pathP = PathJoin(strikeDir, "strike.meta");
    if (pathP == (char *)0) {
        return 0;
    }
    if (!WriteStrikeMeta(pathP, entryP, &fb)) {
        free(pathP);
        return 0;
    }
    free(pathP);

    pathP = PathJoin(strikeDir, "glyphs.meta");
    if (pathP == (char *)0) {
        return 0;
    }
    metaFp = fopen(pathP, "w");
    if (metaFp == (FILE *)0) {
        fprintf(stderr, "fntpatch: cannot write %s\n", pathP);
        free(pathP);
        return 0;
    }
    free(pathP);
    fprintf(metaFp, "glyph_count=%u\n", fb.charCount);
    exported = 0;
    for (i = 0; i < fb.charCount; i++) {
        AnalyzeGlyph(strikeP, &fb, i, entryP->filePos, &glyph);
        charNameP = GeosCharName(glyph.charCode);
        fprintf(metaFp, "glyph.%03u.char_code=%u\n", i, glyph.charCode);
        fprintf(metaFp, "glyph.%03u.char_name=%s\n", i,
                charNameP == (const char *)0 ? "" : charNameP);
        fprintf(metaFp, "glyph.%03u.cte_offset=%u\n", i, glyph.cteOffset);
        fprintf(metaFp, "glyph.%03u.cte_dataOffset=%u\n", i,
                glyph.dataOffset);
        fprintf(metaFp, "glyph.%03u.cte_flags=0x%02x\n", i, glyph.flags);
        fprintf(metaFp, "glyph.%03u.cte_usage=%u\n", i, glyph.usage);
        fprintf(metaFp, "glyph.%03u.cte_width_frac=%u\n", i,
                glyph.widthFrac);
        fprintf(metaFp, "glyph.%03u.cte_width_int=%d\n", i,
                glyph.widthInt);
        fprintf(metaFp, "glyph.%03u.exportable=%u\n", i,
                glyph.exportable ? 1 : 0);
        fprintf(metaFp, "glyph.%03u.reason=%s\n", i, glyph.reason);
        if (glyph.exportable) {
            FormatGlyphPBMPath(fileName, glyph.charCode);
            fprintf(metaFp, "glyph.%03u.cd_pictureWidth=%u\n", i,
                    glyph.pictureWidth);
            fprintf(metaFp, "glyph.%03u.cd_numRows=%u\n", i,
                    glyph.numRows);
            fprintf(metaFp, "glyph.%03u.cd_xoff=%d\n", i, glyph.xoff);
            fprintf(metaFp, "glyph.%03u.cd_yoff=%d\n", i, glyph.yoff);
            fprintf(metaFp, "glyph.%03u.row_byte_count=%u\n", i,
                    glyph.rowBytes);
            fprintf(metaFp, "glyph.%03u.payload_byte_count=%lu\n", i,
                    glyph.payloadBytes);
            fprintf(metaFp, "glyph.%03u.cd_data_file_offset=%lu\n", i,
                    glyph.dataFileOffset);
            fprintf(metaFp, "glyph.%03u.pbm_path=%s\n", i, fileName);
            pathP = PathJoin(strikeDir, fileName);
            if (pathP == (char *)0) {
                fclose(metaFp);
                return 0;
            }
            if (!WritePBM(pathP,
                          strikeP + glyph.dataOffset + CHAR_DATA_HEADER_SIZE,
                          glyph.pictureWidth, glyph.numRows,
                          glyph.rowBytes)) {
                free(pathP);
                fclose(metaFp);
                return 0;
            }
            free(pathP);
            exported++;
        } else {
            fprintf(metaFp, "glyph.%03u.cd_pictureWidth=0\n", i);
            fprintf(metaFp, "glyph.%03u.cd_numRows=0\n", i);
            fprintf(metaFp, "glyph.%03u.cd_xoff=0\n", i);
            fprintf(metaFp, "glyph.%03u.cd_yoff=0\n", i);
            fprintf(metaFp, "glyph.%03u.row_byte_count=0\n", i);
            fprintf(metaFp, "glyph.%03u.payload_byte_count=0\n", i);
            fprintf(metaFp, "glyph.%03u.cd_data_file_offset=0\n", i);
            fprintf(metaFp, "glyph.%03u.pbm_path=\n", i);
        }
    }
    if (fclose(metaFp) != 0) {
        fprintf(stderr, "fntpatch: failed closing glyphs.meta\n");
        return 0;
    }
    *glyphsExportedP += exported;
    return 1;
}

static int DoUnpack(const char *fontPath, const char *fontDir)
{
    FileData file;
    FontHeader hdr;
    PointEntry *entriesP;
    unsigned int count;
    unsigned int i;
    unsigned int exported;
    char **strikeNamesP;
    char pointBuf[16];
    char nameBuf[96];
    char *pathP;
    char *strikesDirP;
    char *strikeDirP;
    char *glyphDirP;
    int ok;

    entriesP = (PointEntry *)0;
    strikeNamesP = (char **)0;
    if (!ReadFile(fontPath, &file)) {
        return 1;
    }
    ok = ParseHeader(&file, &hdr) &&
         LoadPointEntries(&file, &hdr, &entriesP, &count) &&
         CheckUnpackConflicts(fontDir) &&
         EnsureDir(fontDir);
    if (!ok) {
        free(entriesP);
        free(file.dataP);
        return 1;
    }
    strikeNamesP = (char **)calloc(count == 0 ? 1 : count, sizeof(char *));
    if (strikeNamesP == (char **)0) {
        free(entriesP);
        free(file.dataP);
        return 1;
    }
    strikesDirP = PathJoin(fontDir, "strikes");
    pathP = PathJoin(fontDir, "original.fnt");
    if (strikesDirP == (char *)0 || pathP == (char *)0 ||
        !WriteFile(pathP, file.dataP, file.size) ||
        !EnsureDir(strikesDirP)) {
        free(pathP);
        free(strikesDirP);
        free(strikeNamesP);
        free(entriesP);
        free(file.dataP);
        return 1;
    }
    free(pathP);
    exported = 0;
    for (i = 0; i < count; i++) {
        FormatPointSize(entriesP + i, pointBuf);
        sprintf(nameBuf, "%03u_style-%02x_pt-%s", i, entriesP[i].style,
                pointBuf);
        strikeNamesP[i] = DupString(nameBuf);
        if (strikeNamesP[i] == (char *)0) {
            free(strikesDirP);
            free(entriesP);
            free(file.dataP);
            return 1;
        }
        strikeDirP = PathJoin(strikesDirP, strikeNamesP[i]);
        glyphDirP = PathJoin(strikeDirP, "glyphs");
        if (strikeDirP == (char *)0 || glyphDirP == (char *)0 ||
            !EnsureDir(strikeDirP) || !EnsureDir(glyphDirP) ||
            !ExportStrike(strikeDirP, glyphDirP, file.dataP, entriesP + i,
                          &exported)) {
            free(strikeDirP);
            free(glyphDirP);
            free(strikesDirP);
            free(entriesP);
            free(file.dataP);
            return 1;
        }
        free(strikeDirP);
        free(glyphDirP);
    }
    pathP = PathJoin(fontDir, "font.meta");
    ok = pathP != (char *)0 &&
         WriteFontMeta(pathP, fontPath, &hdr, &file, count, strikeNamesP);
    free(pathP);
    for (i = 0; i < count; i++) {
        free(strikeNamesP[i]);
    }
    free(strikeNamesP);
    free(strikesDirP);
    free(entriesP);
    free(file.dataP);
    if (!ok) {
        return 1;
    }
    printf("unpacked %u strikes, exported %u glyphs to %s\n",
           count, exported, fontDir);
    return 0;
}

static char *MetaGet(const TextData *textP, const char *key)
{
    char *scanP;
    char *lineP;
    char *endP;
    size_t keyLen;
    char save;
    char *valueP;
    char *resultP;

    keyLen = strlen(key);
    scanP = textP->dataP;
    while (*scanP != '\0') {
        lineP = scanP;
        endP = strchr(lineP, '\n');
        if (endP == (char *)0) {
            endP = lineP + strlen(lineP);
        }
        if ((size_t)(endP - lineP) > keyLen &&
            strncmp(lineP, key, keyLen) == 0 &&
            lineP[keyLen] == '=') {
            valueP = lineP + keyLen + 1;
            save = *endP;
            *endP = '\0';
            resultP = DupString(valueP);
            *endP = save;
            return resultP;
        }
        scanP = *endP == '\0' ? endP : endP + 1;
    }
    return (char *)0;
}

static int MetaGetULong(const TextData *textP, const char *key,
                        unsigned long *valueP)
{
    char *s;
    char *endP;

    s = MetaGet(textP, key);
    if (s == (char *)0) {
        fprintf(stderr, "fntpatch: missing metadata key %s\n", key);
        return 0;
    }
    *valueP = strtoul(s, &endP, 0);
    if (*endP != '\0') {
        fprintf(stderr, "fntpatch: invalid metadata value %s=%s\n", key, s);
        free(s);
        return 0;
    }
    free(s);
    return 1;
}

static int NextPBMToken(FILE *fp, char *buf, int bufSize)
{
    int c;
    int len;

    do {
        c = fgetc(fp);
        if (c == '#') {
            do {
                c = fgetc(fp);
            } while (c != EOF && c != '\n');
        }
    } while (c != EOF && (c == ' ' || c == '\t' || c == '\r' || c == '\n'));
    if (c == EOF) {
        return 0;
    }
    len = 0;
    while (c != EOF && c != ' ' && c != '\t' && c != '\r' && c != '\n') {
        if (c == '#') {
            do {
                c = fgetc(fp);
            } while (c != EOF && c != '\n');
            break;
        }
        if (len + 1 < bufSize) {
            buf[len++] = (char)c;
        }
        c = fgetc(fp);
    }
    buf[len] = '\0';
    return 1;
}

static int ReadPBM(const char *path, unsigned int expectedWidth,
                   unsigned int expectedHeight, Byte **payloadPP,
                   unsigned long *payloadSizeP)
{
    FILE *fp;
    char token[64];
    unsigned int width;
    unsigned int height;
    unsigned int rowBytes;
    unsigned long payloadSize;
    Byte *payloadP;
    unsigned int row;
    unsigned int col;
    unsigned long value;

    fp = fopen(path, "r");
    if (fp == (FILE *)0) {
        fprintf(stderr, "fntpatch: cannot open %s\n", path);
        return 0;
    }
    if (!NextPBMToken(fp, token, sizeof(token)) || strcmp(token, "P1") != 0 ||
        !NextPBMToken(fp, token, sizeof(token))) {
        fclose(fp);
        fprintf(stderr, "fntpatch: malformed PBM %s\n", path);
        return 0;
    }
    width = (unsigned int)strtoul(token, (char **)0, 10);
    if (!NextPBMToken(fp, token, sizeof(token))) {
        fclose(fp);
        fprintf(stderr, "fntpatch: malformed PBM %s\n", path);
        return 0;
    }
    height = (unsigned int)strtoul(token, (char **)0, 10);
    if (width != expectedWidth || height != expectedHeight) {
        fclose(fp);
        fprintf(stderr, "fntpatch: PBM dimensions mismatch in %s\n", path);
        return 0;
    }
    rowBytes = (width + 7) / 8;
    payloadSize = (unsigned long)rowBytes * height;
    payloadP = (Byte *)calloc(payloadSize == 0 ? 1 : payloadSize, 1);
    if (payloadP == (Byte *)0) {
        fclose(fp);
        return 0;
    }
    for (row = 0; row < height; row++) {
        for (col = 0; col < width; col++) {
            if (!NextPBMToken(fp, token, sizeof(token))) {
                free(payloadP);
                fclose(fp);
                fprintf(stderr, "fntpatch: PBM has too few pixels %s\n",
                        path);
                return 0;
            }
            value = strtoul(token, (char **)0, 10);
            if (value > 1) {
                free(payloadP);
                fclose(fp);
                fprintf(stderr, "fntpatch: PBM pixel is not 0 or 1 %s\n",
                        path);
                return 0;
            }
            if (value != 0) {
                payloadP[row * rowBytes + col / 8] |=
                    (Byte)(0x80 >> (col % 8));
            }
        }
    }
    fclose(fp);
    *payloadPP = payloadP;
    *payloadSizeP = payloadSize;
    return 1;
}

static int PackGlyph(const char *strikeDir, const TextData *glyphMetaP,
                     unsigned int glyphIndex, Byte *fontDataP,
                     unsigned long fontSize, unsigned int *changedP,
                     unsigned int *unchangedP)
{
    char key[80];
    char *pbmRelP;
    char *pbmPathP;
    Byte *payloadP;
    unsigned long width;
    unsigned long height;
    unsigned long rowBytes;
    unsigned long payloadSize;
    unsigned long expectedPayloadSize;
    unsigned long dataFileOffset;
    unsigned long exportable;
    int differs;

    payloadP = (Byte *)0;
    sprintf(key, "glyph.%03u.exportable", glyphIndex);
    if (!MetaGetULong(glyphMetaP, key, &exportable)) {
        return 0;
    }
    sprintf(key, "glyph.%03u.pbm_path", glyphIndex);
    pbmRelP = MetaGet(glyphMetaP, key);
    if (pbmRelP == (char *)0) {
        fprintf(stderr, "fntpatch: missing metadata key %s\n", key);
        return 0;
    }
    if (!exportable || pbmRelP[0] == '\0') {
        free(pbmRelP);
        return 1;
    }
    sprintf(key, "glyph.%03u.cd_pictureWidth", glyphIndex);
    if (!MetaGetULong(glyphMetaP, key, &width)) {
        free(pbmRelP);
        return 0;
    }
    sprintf(key, "glyph.%03u.cd_numRows", glyphIndex);
    if (!MetaGetULong(glyphMetaP, key, &height)) {
        free(pbmRelP);
        return 0;
    }
    sprintf(key, "glyph.%03u.row_byte_count", glyphIndex);
    if (!MetaGetULong(glyphMetaP, key, &rowBytes)) {
        free(pbmRelP);
        return 0;
    }
    sprintf(key, "glyph.%03u.payload_byte_count", glyphIndex);
    if (!MetaGetULong(glyphMetaP, key, &expectedPayloadSize)) {
        free(pbmRelP);
        return 0;
    }
    sprintf(key, "glyph.%03u.cd_data_file_offset", glyphIndex);
    if (!MetaGetULong(glyphMetaP, key, &dataFileOffset)) {
        free(pbmRelP);
        return 0;
    }
    if (((width + 7) / 8) != rowBytes ||
        dataFileOffset + expectedPayloadSize > fontSize) {
        fprintf(stderr, "fntpatch: glyph %03u metadata range is invalid\n",
                glyphIndex);
        free(pbmRelP);
        return 0;
    }
    pbmPathP = PathJoin(strikeDir, pbmRelP);
    free(pbmRelP);
    if (pbmPathP == (char *)0) {
        return 0;
    }
    if (!ReadPBM(pbmPathP, (unsigned int)width, (unsigned int)height,
                 &payloadP, &payloadSize)) {
        free(pbmPathP);
        return 0;
    }
    free(pbmPathP);
    if (payloadSize != expectedPayloadSize) {
        free(payloadP);
        fprintf(stderr, "fntpatch: glyph %03u payload size mismatch\n",
                glyphIndex);
        return 0;
    }
    differs = memcmp(fontDataP + dataFileOffset, payloadP,
                     (size_t)payloadSize) != 0;
    if (differs) {
        memcpy(fontDataP + dataFileOffset, payloadP, (size_t)payloadSize);
        (*changedP)++;
    } else {
        (*unchangedP)++;
    }
    free(payloadP);
    return 1;
}

static int PackStrike(const char *strikeDir, Byte *fontDataP,
                      unsigned long fontSize, unsigned int *validatedP,
                      unsigned int *changedP, unsigned int *unchangedP)
{
    char *pathP;
    TextData glyphMeta;
    unsigned long glyphCount;
    unsigned int i;
    int ok;

    pathP = PathJoin(strikeDir, "glyphs.meta");
    if (pathP == (char *)0) {
        return 0;
    }
    ok = ReadTextFile(pathP, &glyphMeta);
    free(pathP);
    if (!ok) {
        return 0;
    }
    if (!MetaGetULong(&glyphMeta, "glyph_count", &glyphCount) ||
        glyphCount > 256) {
        free(glyphMeta.dataP);
        return 0;
    }
    for (i = 0; i < glyphCount; i++) {
        if (!PackGlyph(strikeDir, &glyphMeta, i, fontDataP, fontSize,
                       changedP, unchangedP)) {
            free(glyphMeta.dataP);
            return 0;
        }
        (*validatedP)++;
    }
    free(glyphMeta.dataP);
    return 1;
}

static int DoPack(const char *fontDir, const char *outPath)
{
    char *pathP;
    char *originalPathP;
    char *strikesDirP;
    char *strikeDirP;
    char key[80];
    char *strikeNameP;
    TextData fontMeta;
    FileData original;
    unsigned long expectedSize;
    unsigned long expectedChecksum;
    unsigned long count;
    unsigned int i;
    unsigned int validated;
    unsigned int changed;
    unsigned int unchanged;
    int ok;

    pathP = PathJoin(fontDir, "font.meta");
    if (pathP == (char *)0) {
        return 1;
    }
    ok = ReadTextFile(pathP, &fontMeta);
    free(pathP);
    if (!ok) {
        return 1;
    }
    originalPathP = PathJoin(fontDir, "original.fnt");
    if (originalPathP == (char *)0 ||
        !ReadFile(originalPathP, &original)) {
        free(originalPathP);
        free(fontMeta.dataP);
        return 1;
    }
    free(originalPathP);
    if (!MetaGetULong(&fontMeta, "font_file_size", &expectedSize) ||
        !MetaGetULong(&fontMeta, "checksum", &expectedChecksum) ||
        !MetaGetULong(&fontMeta, "point_size_count", &count)) {
        free(original.dataP);
        free(fontMeta.dataP);
        return 1;
    }
    if ((unsigned long)original.size != expectedSize ||
        Checksum(original.dataP, original.size) != expectedChecksum) {
        fprintf(stderr, "fntpatch: original.fnt does not match font.meta\n");
        free(original.dataP);
        free(fontMeta.dataP);
        return 1;
    }
    strikesDirP = PathJoin(fontDir, "strikes");
    if (strikesDirP == (char *)0) {
        free(original.dataP);
        free(fontMeta.dataP);
        return 1;
    }
    validated = 0;
    changed = 0;
    unchanged = 0;
    for (i = 0; i < count; i++) {
        sprintf(key, "strike.%03u.dir", i);
        strikeNameP = MetaGet(&fontMeta, key);
        if (strikeNameP == (char *)0) {
            fprintf(stderr, "fntpatch: missing metadata key %s\n", key);
            free(strikesDirP);
            free(original.dataP);
            free(fontMeta.dataP);
            return 1;
        }
        strikeDirP = PathJoin(strikesDirP, strikeNameP);
        free(strikeNameP);
        if (strikeDirP == (char *)0 ||
            !PackStrike(strikeDirP, original.dataP,
                        (unsigned long)original.size, &validated,
                        &changed, &unchanged)) {
            free(strikeDirP);
            free(strikesDirP);
            free(original.dataP);
            free(fontMeta.dataP);
            return 1;
        }
        free(strikeDirP);
    }
    ok = WriteFile(outPath, original.dataP, original.size);
    printf("packed %lu strikes, validated %u glyphs, changed %u, "
           "unchanged %u, wrote %s\n",
           count, validated, changed, unchanged, outPath);
    free(strikesDirP);
    free(original.dataP);
    free(fontMeta.dataP);
    return ok ? 0 : 1;
}

int main(int argc, char **argv)
{
    if (argc != 4) {
        Usage();
        return 1;
    }
    if (strcmp(argv[1], "unpack") == 0) {
        return DoUnpack(argv[2], argv[3]);
    }
    if (strcmp(argv[1], "pack") == 0) {
        return DoPack(argv[2], argv[3]);
    }
    Usage();
    return 1;
}
