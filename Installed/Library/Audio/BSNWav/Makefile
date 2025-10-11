#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = bsnwav
ASMTOOLS        = asmtoolsManager.asm
MAIN            = subcode.goc bsnwav.goc subcode.goh
MP3             = mp3_internal.h minimp3_port.h minimp3.h mp3_play.goc\
                  mp3_decode.goc
QOA             = qoa_decode.goc qoa_play.goc
UI_TO_RDFS      =
OBJS            = subcode.obj bsnwav.obj mp3_play.obj mp3_decode.obj\
                  qoa_decode.obj qoa_play.obj
COMMON          = fmem_compat.h
MODULES         = ASMTOOLS
CMODULES        = Main MP3 QOA
SRCS            = $(ASMTOOLS) $(MAIN) $(MP3) $(QOA) $(COMMON)
LOBJS           =
LIBOBJ          = $(DEVEL_DIR)/Include/$(GEODE).ldf
LIBNAME         = bsnwav

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
