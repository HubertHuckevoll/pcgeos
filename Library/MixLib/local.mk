########################################################################
#
#     Copyright (c) Dirk Lausecker 1997 -- All Rights Reserved
#
# PROJECT:      Best Sound
# MODULE:       Mixer Library
# FILE:         lokal.mk
#
# AUTHOR:       Dirk Lausecker
#
# RCS STAMP:
#   $Id$
#
# DESCRIPTION:
#   Local makefile for the Mixer-Library.
#
# REVISION HISTORY:
#   Date      Name      Description
#   --------  --------  -----------
#   06.10.98  DirkL     Initial Version.
#
########################################################################


#include <$(SYSMAKEFILE)>

GOCFLAGS += -L mixlib
CCOMFLAGS += -WDE -w
# CCOMFLAGS += -O2 -w -w-amp -w-cln -w-pin
# LINKFLAGS += -N Copyright\20Dirk\20Lausecker\201998
