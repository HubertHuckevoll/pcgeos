/* Native PDF 1.1 writer. No page buffer, seek, stdio or host service. */
#ifndef PDF_WRITER_H
#define PDF_WRITER_H
#ifdef PDF_HOST_TEST
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
#define PDF_FIRST_PAGE_OBJECT 7
#define PDF_MAX_OBJECTS (PDF_FIRST_PAGE_OBJECT + 3 * PDF_MAX_PAGES)
#define PDF_BUFFER_SIZE 512
#define PDF_OK 0
#define PDF_IO_ERROR 1
#define PDF_LIMIT_ERROR 2
#define PDF_STATE_ERROR 3
#define PDF_UNSUPPORTED 4
/* All state is per job. The caller owns and locks this block while in use. */
typedef struct {
    PdfWord token;
    void (*strategy)(void);
    PdfWord error, pages, inPage, finished, transformed, width, height, used;
    PdfDWord position, contentStart;
    PdfDWord offsets[PDF_MAX_OBJECTS];
    unsigned char buffer[PDF_BUFFER_SIZE];
} PdfDocument;
/* Platform adapter: return zero ONLY if all bytes were written. */
PdfWord PdfSink(PdfDocument *pdf, const void *data, PdfWord size);
void PdfRaw(PdfDocument *pdf, const char *text);
void PdfUnsigned(PdfDocument *pdf, PdfDWord value);
void PdfNumber(PdfDocument *pdf, PdfFixed value);
void PdfInteger(PdfDocument *pdf, PdfFixed value);
void PdfFlush(PdfDocument *pdf);
void PdfBegin(PdfDocument *pdf);
void PdfBeginPage(PdfDocument *pdf);
void PdfPageMatrix(PdfDocument *pdf, const PdfFixed *matrix);
void PdfEndPage(PdfDocument *pdf);
void PdfFinish(PdfDocument *pdf);
void PdfColor(PdfDocument *pdf, PdfDWord rgb, int stroke);
void PdfText(PdfDocument *pdf, int x, int y, PdfFixed size,
             PdfWord font, const unsigned char *text, PdfWord count);
#endif
