GEODE = pdf
LIBNAME = print
PROTOCONST = PRINT
ASM_TO_OBJS = pdfManager.asm
UI_TO_RDFS =
SRCS = pdfManager.asm pdfJob.asm pdfPDL.asm pdfInfo.asm pdfDriverInfo.asm
OBJS = pdfManager.obj
LOBJS =
SYSMAKEFILE = geode.mk
#include <geos.mk>
#include <gpath.mk>
#if exists(local.mk)
#include "local.mk"
#else
#include <$(SYSMAKEFILE)>
#endif
#if exists($(DEPFILE))
#include "$(DEPFILE)"
#endif
