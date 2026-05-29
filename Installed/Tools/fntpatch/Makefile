##############################################################################
#
# PROJECT:	PC GEOS
# MODULE:	fntpatch -- Makefile
# FILE: 	Makefile
#
# DESCRIPTION:
#	Host-side GEOS bitmap font patching tool.
#
###############################################################################


#include	<geos.mk>
#include	<gpath.mk>

MACHINES	= linux win32
MAKEFILE	= Makefile
NAME		= fntpatch
SYSMAKEFILE	= tool.mk
TYPE		= tool

#if	defined(linux)
DEFTARGET	= linux
#else
DEFTARGET	= win32
#endif

MISRCS          = fntpatch.c nimbus.h

linuxSRCS       = $(MISRCS) linux.md/
linuxOBJS       = linux.md/fntpatch.o
linuxLIBS       =

win32SRCS       = $(MISRCS) win32.md/
win32OBJS       = win32.md/fntpatch.obj
win32LIBS       =


SUBDIRS         =

#if exists(local.mk)
#include	"local.mk"
#else
#include	<$(SYSMAKEFILE)>
#endif

#if	exists(linux.md/dependencies.mk)
#include	"linux.md/dependencies.mk"
#endif

#if	exists(win32.md/dependencies.mk)
#include	"win32.md/dependencies.mk"
#endif


# Allow mkmf
