#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = svglib
IMPORT          = svgPathSyntax.c svgRendererCore.c svgCapacity.h\
                  svgPathSyntax.h svg.h dbglog.h svgRendererCore.h\
                  svgGeom.goc svgPath.goc svgRenderer.goc svgShape.goc\
                  svgStyle.goc svgTransform.goc svgUtil.goc svgView.goc\
                  svgParse.goc svg.goc dbglog.goc svgApi.goc colors.goh
EXPORT          = svgWriter.c svgExport.h svgWriter.h svgExport.goc\
                  svgExportDecode.goc svgExportWriter.goc
UI_TO_RDFS      =
OBJS            = svgPathSyntax.obj svgRendererCore.obj svgGeom.obj\
                  svgPath.obj svgRenderer.obj svgShape.obj svgStyle.obj\
                  svgTransform.obj svgUtil.obj svgView.obj svgParse.obj\
                  svg.obj dbglog.obj svgApi.obj svgWriter.obj svgExport.obj\
                  svgExportDecode.obj svgExportWriter.obj
COMMON          =
MODULES         =
CMODULES        = Import Export
SRCS            = $(IMPORT) $(EXPORT) $(COMMON)
LOBJS           =
LIBOBJ          = $(DEVEL_DIR)/Include/$(GEODE).ldf
LIBNAME         = svglib

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
