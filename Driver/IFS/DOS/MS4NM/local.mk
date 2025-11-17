# $Id$

.PATH.asm .PATH.def : ../Common $(INSTALL_DIR:H)/Common

PROTOCONST      = FS

#include <$(SYSMAKEFILE)>

#
# If the target is "XIP" then specify the conditional
# compilation directives on the command line for the assembler.
#
ASMFLAGS        += $(.TARGET:X\\[XIP\\]/*:S|XIP| -DFULL_EXECUTE_IN_PLACE=TRUE |g)

#full           :: XIP

#
# NetMount-aware builds are otherwise identical to MS4 and do not
# require additional build flags at this level.
#
