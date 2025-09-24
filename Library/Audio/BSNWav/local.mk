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


#include <$(SYSMAKEFILE)>

GOCFLAGS += -L bsnwav
ASM_TO_OBJS    += ASMTOOLS/asmtoolsManager.asm
OBJS            += ASMTOOLS/asmtoolsManager.obj
SRCS            += ASMTOOLS/asmtoolsManager.asm

# CCOMFLAGS += -WDE -w
# CCOMFLAGS += -O2 -w -w-amp -w-cln -w-pin
# LINKFLAGS += -N Copyright\20Dirk\20Lausecker\202000

