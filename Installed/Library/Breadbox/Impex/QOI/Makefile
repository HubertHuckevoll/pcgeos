#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = qoi
API             = apiManager.asm qoi.def
XLAT            = expqoi.goc impqoi.goc
UI_TO_RDFS      = manager.ui
OBJS            = expqoi.obj impqoi.obj
COMMON          =
MODULES         = API
CMODULES        = Xlat
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
