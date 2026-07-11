#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = markdown
EXPORT          = exportManager.asm exportMain.asm exportMarkdown.goc
IMPORT          = importManager.asm importMain.asm importConstant.def\
                  markdownImport.goc
LIB             = libFormat.asm libManager.asm
UI_TO_RDFS      =
OBJS            = exportMarkdown.obj markdownImport.obj
COMMON          = asciiConstant.def asciiGeode.def html4par.def
MODULES         = Export Import Lib
CMODULES        = Export Import
SRCS            = $(EXPORT) $(IMPORT) $(LIB) $(COMMON)
LOBJS           =
LIBOBJ          = $(DEVEL_DIR)/Include/$(GEODE).ldf
LIBNAME         = markdown

SYSMAKEFILE     = geode.mk

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
