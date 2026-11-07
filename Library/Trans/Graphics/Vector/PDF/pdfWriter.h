/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

PROJECT:    PC/GEOS
MODULE:     Native PDF Translation Library
FILE:       pdfWriter.h

AUTHOR:     Codex/MeyerK, Nov 2026

FUNCTIONS:
    PdfDocument - Per-job PDF serialization context
    PdfBegin    - Begin PDF output
    PdfFinish   - Write trailer and cross-reference table

REVISION HISTORY:
    Name            Date        Description
    ----            ----        -----------
    Codex/MeyerK    11/07/26    Add GeoWorks-style module header.

DESCRIPTION:
    Declare PDF writer types, limits, error codes and public routines.
    Keep the document state in a caller-owned memory block.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/

/* Native PDF 1.1 writer. No page buffer, seek, stdio or host service. */
#ifndef PDF_WRITER_H
#define PDF_WRITER_H
#ifdef PDF_HOST_TEST
#ifndef _pascal
#define _pascal
#endif
#include <stdint.h>
typedef uint16_t PdfWord;
typedef uint32_t PdfDWord;
typedef int32_t PdfFixed;
#else
#include <geos.h>
typedef word PdfWord;
typedef dword PdfDWord;
typedef sdword PdfFixed;
#endif
#define PDF_MAX_PAGES 256
#define PDF_FONT_COUNT 14
#define PDF_FONT_SYMBOL 12
#define PDF_FONT_DINGBATS 13
#define PDF_FIRST_PAGE_OBJECT (3 + PDF_FONT_COUNT)
#define PDF_MAX_OBJECTS (PDF_FIRST_PAGE_OBJECT + 3 * PDF_MAX_PAGES)
#define PDF_BUFFER_SIZE 512
#define PDF_DEVICE_DPI 300
#define PDF_OK 0
#define PDF_IO_ERROR 1
#define PDF_LIMIT_ERROR 2
#define PDF_STATE_ERROR 3
#define PDF_UNSUPPORTED 4
typedef void _pascal PdfPointTransform(void *context, PdfFixed *xP, PdfFixed *yP);
/* All state is per job. The caller owns and locks this block while in use. */
typedef struct {
    PdfWord token;
    void (*strategy)(void);
    PdfWord error, pages, inPage, finished, transformed, width, height, used, imageOpen;
    PdfDWord position, contentStart;
    PdfFixed pageMatrix[6];
    PdfWord deviceH, pathStateH, pathPaintH;
    PdfPointTransform *pathTransform;
    PdfDWord offsets[PDF_MAX_OBJECTS];
    unsigned char buffer[PDF_BUFFER_SIZE];
} PdfDocument;
/* Platform adapter: return zero ONLY if all bytes were written. */
PdfWord PdfSink(PdfDocument *pdf, const void *data, PdfWord size);
void PdfRaw(PdfDocument *pdf, const char *text);
void PdfUnsigned(PdfDocument *pdf, PdfDWord value);
void PdfNumber(PdfDocument *pdf, PdfFixed value);
void PdfInteger(PdfDocument *pdf, PdfFixed value);
void _pascal PdfPathPoint(PdfDocument *pdf, PdfFixed x, PdfFixed y);
void _pascal PdfPathRect(PdfDocument *pdf, PdfFixed x1, PdfFixed y1, PdfFixed x2, PdfFixed y2);
void PdfFlush(PdfDocument *pdf);
void PdfBegin(PdfDocument *pdf);
void PdfBeginPage(PdfDocument *pdf);
/* Set once per page; apply inside each object, after physical clipping. */
void PdfPageMatrix(PdfDocument *pdf, const PdfFixed *matrix);
void PdfApplyPageMatrix(PdfDocument *pdf);
void PdfEndPage(PdfDocument *pdf);
void PdfFinish(PdfDocument *pdf);
void PdfColor(PdfDocument *pdf, PdfDWord rgb, int stroke);
/* Signed 16-bit GEOS bounds; reversed corners accepted. fill=-1 appends
 * construction operators only, preserving the current PDF path. */
void PdfEllipse(PdfDocument *pdf, int x1, int y1, int x2, int y2, int fill);
void PdfRoundRect(PdfDocument *pdf, int x1, int y1, int x2, int y2,
                  PdfWord radius, int fill);
void PdfArc(PdfDocument *pdf, int x1, int y1, int x2, int y2,
             int start, int end, PdfWord close, int fill, PdfFixed *startP);
void PdfThreePointArc(PdfDocument *pdf, const PdfFixed *pointsP, PdfWord close, int fill);
void PdfBrushSegment(PdfDocument *pdf, PdfFixed x1, PdfFixed y1,
                      PdfFixed x2, PdfFixed y2, PdfWord width, PdfWord height);
void PdfText(PdfDocument *pdf, PdfFixed x, PdfFixed y, PdfFixed size,
             PdfWord font, const unsigned char *text, PdfWord count);
#endif
