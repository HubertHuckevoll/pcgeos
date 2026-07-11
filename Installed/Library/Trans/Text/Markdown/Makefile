#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = markdown
EXPORT          = exportMain.asm exportManager.asm
IMPORT          = importMain.asm importManager.asm markdownRich.asm\
                  importConstant.def
LIB             = libFormat.asm libManager.asm
UI_TO_RDFS      =
OBJS            =
COMMON          = asciiConstant.def asciiGeode.def html4par.def
MODULES         = Export Import Lib
CMODULES        =
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
