#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = meta
CGM             = cgm.h cgm.goc cgmraw.goc
HPGL            = hpgl.goc
SVG             = dbglog.h svg.h dbglog.goc svg.goc svgGeom.goc\
                  svgShape.goc svgTransform.goc svgUtil.goc svgView.goc\
                  svgPath.goc svgStyle.goc colors.goh
META            = meta.goc
SPLINEOP        = splineop.goc
UI_TO_RDFS      =
OBJS            = cgm.obj cgmraw.obj hpgl.obj dbglog.obj svg.obj\
                  svgGeom.obj svgShape.obj svgTransform.obj svgUtil.obj\
                  svgView.obj svgPath.obj svgStyle.obj meta.obj\
                  splineop.obj
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
