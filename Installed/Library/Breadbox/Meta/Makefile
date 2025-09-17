#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = meta
CGM             = cgm.h cgm.goc cgmraw.goc
HPGL            = hpgl.goc
SVG             = dbglog.h svg.h dbglog.goc svgGeom.goc svgView.goc\
                  svgTransform.goc svg.goc svgParse.goc svgPath.goc\
                  svgShape.goc svgStyle.goc svgUtil.goc colors.goh
META            = meta.goc
SPLINEOP        = splineop.goc
UI_TO_RDFS      =
OBJS            = cgm.obj cgmraw.obj hpgl.obj dbglog.obj svgGeom.obj\
                  svgView.obj svgTransform.obj svg.obj svgParse.obj\
                  svgPath.obj svgShape.obj svgStyle.obj svgUtil.obj\
                  meta.obj splineop.obj
COMMON          = metaint.h
MODULES         =
CMODULES        = CGM HPGL SVG meta splineop
SRCS            = $(CGM) $(HPGL) $(SVG) $(META) $(SPLINEOP) $(COMMON)
LOBJS           =
LIBOBJ          = $(DEVEL_DIR)/Include/$(GEODE).ldf
LIBNAME         = meta

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
