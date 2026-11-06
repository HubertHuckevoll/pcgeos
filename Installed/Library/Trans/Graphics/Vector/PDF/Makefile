GEODE = pdf
LIBNAME = pdf
ASM_TO_OBJS = pdfStream.asm
UI_TO_RDFS =
SRCS = pdfWriter.c pdfGeos.c pdfWriter.h pdfStream.asm
OBJS = pdfWriter.obj pdfGeos.obj pdfStream.obj
LOBJS =
LIBOBJ = $(DEVEL_DIR)/Include/$(GEODE).ldf
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
