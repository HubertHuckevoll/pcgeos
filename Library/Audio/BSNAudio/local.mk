########################################################################
#
#     Copyright (c) Dirk Lausecker 2000 -- All Rights Reserved
#
# PROJECT:      Best Sound
# MODULE:       NewWave-Library
# FILE:         lokal.mk
#
# AUTHOR:       Dirk Lausecker
#
# RCS STAMP:
#   $Id$
#
# DESCRIPTION:
#   Local makefile for the BestSound NewWave-Library.
#
# REVISION HISTORY:
#   Date      Name      Description
#   --------  --------  -----------
#   06.10.98  DirkL     Initial Version.
#	2000	  DL		Von Recording Library abgeleitet
#
########################################################################


# Keep the permanent geode name while the source directory is BSNAudio.
GEODE = bsnwav
# geos.mk reads revisions before this GEODE override.
_PROTO != grev getproto $(INSTALL_DIR)/bsnwav.rev -P
_REL != grev neweng $(INSTALL_DIR)/bsnwav.rev -R
# The reference multiplier is compiled out for GEOS; do not link an empty
# Watcom CodeView type stream (older glue versions cannot process it).
OBJS := $(OBJS:Nmp3fxp.obj)
EOBJS := $(EOBJS:Nmp3fxp.eobj)
GOBJS := $(GOBJS:Nmp3fxp.gobj)
#include <$(SYSMAKEFILE)>

GOCFLAGS += -L bsnwav
# ASM_TO_OBJS    += ASMTOOLS/asmtoolsManager.asm
# OBJS            += ASMTOOLS/asmtoolsManager.obj
# SRCS            += ASMTOOLS/asmtoolsManager.asm

# CCOMFLAGS += -WDE -w
# CCOMFLAGS += -O2 -w -w-amp -w-cln -w-pin
# LINKFLAGS += -N Copyright\20Dirk\20Lausecker\202000


# Preserve the decoder's Pascal internals and directly addressed fixed tables.
# ATTENTION: Do not select -zc: cross-resource table references need a real
# segment. Move tables behind locked-handle access before changing placement.
XCCOMFLAGS += -ecp
