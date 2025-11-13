#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = qoi
API             = apiManager.asm qoi.def ui.goc
XLAT            = expqoi.c impqoi.c
UI_TO_RDFS      =
OBJS            = ui.obj expqoi.obj impqoi.obj
COMMON          =
MODULES         = API
CMODULES        = API Xlat
SRCS            = $(API) $(XLAT) $(COMMON)
LOBJS           =
LIBOBJ          = $(DEVEL_DIR)/Include/$(GEODE).ldf
LIBNAME         = qoi

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
