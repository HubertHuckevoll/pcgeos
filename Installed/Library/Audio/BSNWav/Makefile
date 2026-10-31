#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = bsnwav
MAIN            = subcode.goc library.goc subcode.goh
PCM             = pcm.goc
WAV             = wav.goc
MP3DEC          = mp3decManager.asm mp3api.c mp3frame.c mp3fxp.c mp3huff.c\
                  mp3imdct.c mp3quant.c mp3ster.c mp3synth.c mp3fxp.h\
                  mp3int.h mp3dec.h mp3reader.goc
DRIVER          = driverManager.asm
UI_TO_RDFS      =
OBJS            = subcode.obj library.obj pcm.obj wav.obj mp3api.obj\
                  mp3frame.obj mp3fxp.obj mp3huff.obj mp3imdct.obj\
                  mp3quant.obj mp3ster.obj mp3synth.obj mp3reader.obj
COMMON          =
MODULES         = MP3Dec Driver
CMODULES        = Main PCM WAV MP3Dec
SRCS            = $(MAIN) $(PCM) $(WAV) $(MP3DEC) $(DRIVER) $(COMMON)
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
