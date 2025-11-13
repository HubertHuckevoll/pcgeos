/*
 *  qoilib.goc — QOI -> GEOS 24-bit bitmap importer (true color only)
 *
 *  Output: BMF_24BIT | BMT_COMPLEX [| BMT_MASK if any A<255 encountered]
 *  API:    QoiImportBitmapFName, QoiImportBitmapFHandle,
 *          QoiImportTestBitmapFName, QoiImportTestBitmapFHandle
 */

#include <geos.h>
#include <heap.h>
#include <vm.h>
#include <file.h>
#include <hugearr.h>
#include <Ansi/string.h>
#include <graphics.h>
#include <extgraph.h>
#include <qoilib.h>      /* public prototypes + QoiError */


/* Legacy compatibility transform state (mirrors old setters) */
static QoiAlphaTransformData g_qoiLegacyTransform =
{
    QOI_AT_MASK,
    255,
    {0, 0, 0}
};


/**********************************************************************
*   LOCAL HELPERS
**********************************************************************/

static Boolean
qoiReadByte(FileHandle fh, byte *out)
{
    int rd;
    rd = FileRead(fh, out, 1, 0);
    if (rd == 1) { return TRUE; }
    return FALSE;
}

static Boolean
qoiReadN(FileHandle fh, void *buf, word n)
{
    int rd;
    rd = FileRead(fh, buf, n, 0);
    if (rd == (int)n) { return TRUE; }
    return FALSE;
}

static dword
qoiBE32ToHost(dword be)
{
    dword v;
    byte *p;
    p = (byte*) &be;
    v = ((dword)p[0] << 24) | ((dword)p[1] << 16) | ((dword)p[2] << 8) | (dword)p[3];
    return v;
}

static word
qoiClampWordFromDword(dword v)
{
    if (v > 65535UL) { return 65535; }
    return (word)v;
}

/* hash per QOI spec: (r*3 + g*5 + b*7 + a*11) % 64 */
static byte
qoiHash(QoiRGBA px)
{
    word s;
    s = (word)px.r * 3 + (word)px.g * 5 + (word)px.b * 7 + (word)px.a * 11;
    return (byte)(s & 63);
}

static void
qoiInitDefaultTransform(QoiAlphaTransformData *out)
{
    out->QATD_method = QOI_AT_MASK;
    out->QATD_alphaThreshold = 255;
    out->QATD_blendColor.RGB_red = 255;
    out->QATD_blendColor.RGB_green = 255;
    out->QATD_blendColor.RGB_blue = 255;
}

static void
qoiNormalizeTransform(const QoiAlphaTransformData *src,
                      QoiAlphaTransformData *dst)
{
    qoiInitDefaultTransform(dst);

    if (src != NULL)
    {
        dst->QATD_method = src->QATD_method;
        dst->QATD_alphaThreshold = src->QATD_alphaThreshold;
        dst->QATD_blendColor = src->QATD_blendColor;
    }

    if (!(dst->QATD_method == QOI_AT_MASK || dst->QATD_method == QOI_AT_BLEND))
    {
        dst->QATD_method = QOI_AT_MASK;
    }
}


void _pascal _export
QoiImportSetAlphaThreshold(byte threshold)
{
    g_qoiLegacyTransform.QATD_alphaThreshold = threshold;
}

void _pascal _export
QoiImportSetBlendColor(byte r, byte g, byte b)
{
    g_qoiLegacyTransform.QATD_blendColor.RGB_red = r;
    g_qoiLegacyTransform.QATD_blendColor.RGB_green = g;
    g_qoiLegacyTransform.QATD_blendColor.RGB_blue = b;
}

void _pascal _export
QoiImportSetBlendEnabled(Boolean on)
{
    if (on)
    {
        g_qoiLegacyTransform.QATD_method = QOI_AT_BLEND;
    }
    else
    {
        g_qoiLegacyTransform.QATD_method = QOI_AT_MASK;
    }
}

/**********************************************************************
*   CORE DECODER — TRUE COLOR (24-bit + optional 1-bit mask)
**********************************************************************/

static QoiError
qoiDecodeTo24Bit(FileHandle fh, qoiOutStream *os, byte channels,
                 const QoiAlphaTransformData *transform)
{
    QoiRGBA index[64];
    QoiRGBA px;
    word x;
    word y;
    word i;
    dword run;
    byte *lineBase;
    byte *scan;
    byte *maskBase;
    word maskIdx;
    byte maskBit;
    MemHandle line;
    byte b;
    byte b2;
    Boolean ok;
    word maskBytes;
    void *lineptr;
    word size;
    Boolean useMask;
    Boolean doBlend;
    byte threshold;
    RGBValue blendColor;
    byte r8;
    byte g8;
    byte b8;
    word a16;
    word ia16;

    useMask = FALSE;
    doBlend = FALSE;
    threshold = 255;
    blendColor = transform->QATD_blendColor;

    if (channels == 4)
    {
        if (transform->QATD_method == QOI_AT_MASK)
        {
            useMask = TRUE;
            threshold = transform->QATD_alphaThreshold;
        }
        else if (transform->QATD_method == QOI_AT_BLEND)
        {
            doBlend = TRUE;
        }
    }

    for (i = 0; i < 64; i++)
    {
        index[i].r = 0;
        index[i].g = 0;
        index[i].b = 0;
        index[i].a = 255;
    }
    px.r = 0;
    px.g = 0;
    px.b = 0;
    px.a = 255;

    maskBytes = useMask ? (word)((os->QOS_width + 7) / 8) : 0;

    os->QOS_maskoff = 0;
    os->QOS_stride = (word)(maskBytes + os->QOS_width * 3);

    line = os->QOS_line;
    lineBase = (byte*)MemLock(line);
    if (lineBase == NULL)
    {
        return QE_OUT_OF_MEMORY;
    }
    maskBase = lineBase;
    scan = lineBase + maskBytes;

    run = 0;

    for (y = 0; y < os->QOS_height; y++)
    {
        if (useMask)
        {
            for (i = 0; i < maskBytes; i++)
            {
                maskBase[i] = 0;
            }
        }

        maskIdx = 0;
        maskBit = 0;

        for (x = 0; x < os->QOS_width; x++)
        {
            if (run > 0)
            {
                run--;
            }
            else
            {
                ok = qoiReadByte(fh, &b);
                if (!ok)
                {
                    MemUnlock(line);
                    return QE_OUT_OF_DATA;
                }

                if (b == QOI_OP_RGB)
                {
                    ok = qoiReadByte(fh, &px.r);
                    if (!ok) { MemUnlock(line); return QE_OUT_OF_DATA; }
                    ok = qoiReadByte(fh, &px.g);
                    if (!ok) { MemUnlock(line); return QE_OUT_OF_DATA; }
                    ok = qoiReadByte(fh, &px.b);
                    if (!ok) { MemUnlock(line); return QE_OUT_OF_DATA; }
                }
                else if (b == QOI_OP_RGBA)
                {
                    ok = qoiReadByte(fh, &px.r);
                    if (!ok) { MemUnlock(line); return QE_OUT_OF_DATA; }
                    ok = qoiReadByte(fh, &px.g);
                    if (!ok) { MemUnlock(line); return QE_OUT_OF_DATA; }
                    ok = qoiReadByte(fh, &px.b);
                    if (!ok) { MemUnlock(line); return QE_OUT_OF_DATA; }
                    ok = qoiReadByte(fh, &px.a);
                    if (!ok) { MemUnlock(line); return QE_OUT_OF_DATA; }
                }
                else
                {
                    switch (b & QOI_MASK_2)
                    {
                        case QOI_OP_INDEX:
                        {
                            px = index[b];
                            break;
                        }
                        case QOI_OP_DIFF:
                        {
                            px.r = (byte)(px.r + (((b >> 4) & 0x03) - 2));
                            px.g = (byte)(px.g + (((b >> 2) & 0x03) - 2));
                            px.b = (byte)(px.b + ((b & 0x03) - 2));
                            break;
                        }
                        case QOI_OP_LUMA:
                        {
                            ok = qoiReadByte(fh, &b2);
                            if (!ok)
                            {
                                MemUnlock(line);
                                return QE_OUT_OF_DATA;
                            }
                            {
                                int dg;
                                int dr;
                                int db;

                                dg = ((b & 0x3f) - 32);
                                dr = (int)((b2 >> 4) & 0x0f) - 8 + dg;
                                db = (int)(b2 & 0x0f) - 8 + dg;
                                px.g = (byte)((int)px.g + dg);
                                px.r = (byte)((int)px.r + dr);
                                px.b = (byte)((int)px.b + db);
                            }
                            break;
                        }
                        case QOI_OP_RUN:
                        {
                            run = (b & 0x3f);
                            break;
                        }
                    }
                }

                index[qoiHash(px)] = px;
            }

            r8 = px.r;
            g8 = px.g;
            b8 = px.b;

            if (channels == 4)
            {
                if (useMask)
                {
                    if (px.a >= threshold)
                    {
                        maskBase[maskIdx] |= (byte)(0x80 >> maskBit);
                    }
                    else
                    {
                        os->QOS_hasAlpha = TRUE;
                    }
                }
                else if (px.a < 255)
                {
                    os->QOS_hasAlpha = TRUE;
                }

                if (doBlend && px.a < 255)
                {
                    a16 = (word)px.a;
                    ia16 = (word)(255 - px.a);

                    r8 = (byte)(((word)r8 * a16 +
                                (word)blendColor.RGB_red * ia16 + 127) / 255);
                    g8 = (byte)(((word)g8 * a16 +
                                (word)blendColor.RGB_green * ia16 + 127) / 255);
                    b8 = (byte)(((word)b8 * a16 +
                                (word)blendColor.RGB_blue * ia16 + 127) / 255);
                }

                if (useMask)
                {
                    maskBit++;
                    if (maskBit == 8)
                    {
                        maskBit = 0;
                        maskIdx++;
                    }
                }
            }

            scan[x * 3 + 0] = r8;
            scan[x * 3 + 1] = g8;
            scan[x * 3 + 2] = b8;
        }

        if (HAL_COUNT(HugeArrayLock(os->QOS_file, os->QOS_block,
                                    (dword)y, &lineptr, &size)) != 0)
        {
            memcpy(lineptr, (void*)MemDeref(line), os->QOS_stride);
            HugeArrayDirty(lineptr);
            HugeArrayUnlock(lineptr);
        }
        else
        {
            MemUnlock(line);
            return QE_INVALID_FILE;
        }
    }

    {
        byte tail[8];
        ok = qoiReadN(fh, tail, 8);
        if (!ok)
        {
            MemUnlock(line);
            return QE_OUT_OF_DATA;
        }
    }

    MemUnlock(line);
    return QE_NO_ERROR;
}

/**********************************************************************
*   PUBLIC API
**********************************************************************/

VMBlockHandle _pascal _export
QoiImportBitmapFNameWithTransform(PathName srcname, VMFileHandle destfile,
                                  const QoiAlphaTransformData *transform,
                                  QoiError *error)
{
    FileHandle srcfile;
    QoiError stat;
    VMBlockHandle bmblock;

    srcfile = FileOpen(srcname, FILE_ACCESS_W | FILE_DENY_RW);
    if (srcfile)
    {
        bmblock = QoiImportBitmapFHandleWithTransform(srcfile, destfile,
                                                      transform, &stat);
        FileClose(srcfile, 0);
    }
    else
    {
        stat = QE_CANT_OPEN_SOURCE_FILE;
        bmblock = 0;
    }

    if (error)
    {
        *error = stat;
    }
    return bmblock;
}

VMBlockHandle _pascal _export
QoiImportBitmapFHandleWithTransform(FileHandle srcfile, VMFileHandle destfile,
                                    const QoiAlphaTransformData *transform,
                                    QoiError *error)
{
    QoiAlphaTransformData opts;
    QoiError stat;
    QoiHeaderOnDisk hd;
    dword Wd;
    dword Hd;
    word W;
    word H;
    byte channels;
    byte colorspace;
    qoiOutStream os;
    GStateHandle bmstate;
    BMFormat bmformat;
    MemHandle line;
    word lineBytes;
    word maskBytes;
    Boolean useMask;

    stat = QE_NO_ERROR;
    line = 0;
    os.QOS_block = 0;

    qoiNormalizeTransform(transform, &opts);

    if (FilePos(srcfile, 0, FILE_POS_START) != 0)
    {
        stat = QE_INVALID_FILE;
        goto done;
    }
    if (!qoiReadN(srcfile, (void*)&hd, (word)sizeof(QoiHeaderOnDisk)))
    {
        stat = QE_WRONG_FILE_FORMAT;
        goto done;
    }
    if (hd.magic[0] != QOI_MAGIC_0 || hd.magic[1] != QOI_MAGIC_1 ||
        hd.magic[2] != QOI_MAGIC_2 || hd.magic[3] != QOI_MAGIC_3)
    {
        stat = QE_WRONG_FILE_FORMAT;
        goto done;
    }

    Wd = qoiBE32ToHost(hd.widthBE);
    Hd = qoiBE32ToHost(hd.heightBE);
    W = qoiClampWordFromDword(Wd);
    H = qoiClampWordFromDword(Hd);

    channels = hd.channels;
    colorspace = hd.colorspace;
    (void)colorspace;

    if (!(channels == 3 || channels == 4))
    {
        stat = QE_WRONG_FILE_FORMAT;
        goto done;
    }

    useMask = (Boolean)((channels == 4) && (opts.QATD_method == QOI_AT_MASK));

    bmformat = (BMFormat)(BMF_24BIT | BMT_COMPLEX);
    if (useMask)
    {
        bmformat = (BMFormat)(bmformat | BMT_MASK);
    }

    os.QOS_block = GrCreateBitmap(bmformat, W, H, destfile, 0, &bmstate);
    if (os.QOS_block == 0)
    {
        stat = QE_OUT_OF_MEMORY;
        goto done;
    }
    GrDestroyBitmap(bmstate, BMD_LEAVE_DATA);

    lineBytes = (word)(W * 3);
    maskBytes = useMask ? (word)((W + 7) / 8) : 0;

    line = MemAlloc((word)(lineBytes + maskBytes), HF_SWAPABLE, 0);
    if (line == 0)
    {
        stat = QE_OUT_OF_MEMORY;
        goto fail_free_bitmap;
    }

    os.QOS_file = destfile;
    os.QOS_width = W;
    os.QOS_height = H;
    os.QOS_format = (BMFormat)(bmformat & ~BMT_MASK);
    os.QOS_line = line;
    os.QOS_hasAlpha = FALSE;
    os.QOS_y = 0;

    stat = qoiDecodeTo24Bit(srcfile, &os, channels, &opts);

    MemFree(line);
    line = 0;

    if (stat != QE_NO_ERROR)
    {
        goto fail_free_bitmap;
    }

    goto done;

fail_free_bitmap:
    if (os.QOS_block != 0)
    {
        VMFreeVMChain(destfile, VMCHAIN_MAKE_FROM_VM_BLOCK(os.QOS_block));
        os.QOS_block = 0;
    }

done:
    if (line != 0)
    {
        MemFree(line);
    }
    if (error)
    {
        *error = stat;
    }
    return os.QOS_block;
}

VMBlockHandle _pascal _export
QoiImportBitmapFName(PathName srcname, VMFileHandle destfile, QoiError *error)
{
    return QoiImportBitmapFNameWithTransform(srcname, destfile,
                                             &g_qoiLegacyTransform, error);
}

VMBlockHandle _pascal _export
QoiImportBitmapFHandle(FileHandle srcfile, VMFileHandle destfile, QoiError *error)
{
    return QoiImportBitmapFHandleWithTransform(srcfile, destfile,
                                               &g_qoiLegacyTransform, error);
}

QoiError _pascal _export
QoiImportTestBitmapFName(PathName srcname)
{
    FileHandle srcfile;
    QoiError stat;

    srcfile = FileOpen(srcname, FILE_ACCESS_W | FILE_DENY_RW);
    if (srcfile)
    {
        stat = QoiImportTestBitmapFHandle(srcfile);
        FileClose(srcfile, 0);
    }
    else
    {
        stat = QE_CANT_OPEN_SOURCE_FILE;
    }

    return stat;
}

QoiError _pascal _export
QoiImportTestBitmapFHandle(FileHandle srcfile)
{
    byte magic[4];
    int rd;

    FilePos(srcfile, 0, FILE_POS_START);

    rd = FileRead(srcfile, (void*)&magic[0], 4, 0);
    if (rd != 4)
        return QE_INVALID_FILE;

    if (magic[0] == QOI_MAGIC_0 &&
        magic[1] == QOI_MAGIC_1 &&
        magic[2] == QOI_MAGIC_2 &&
        magic[3] == QOI_MAGIC_3)
    {
        return QE_NO_ERROR;
    }

    return QE_WRONG_FILE_FORMAT;
}
