##############################################################################
#
# PROJECT:    PC/GEOS
# MODULE:     Native PDF Printer Driver
# FILE:       local.mk
#
# AUTHOR:     Codex/MeyerK, Nov 2026
#
# REVISION HISTORY:
#     Name            Date        Description
#     ----            ----        -----------
#     Codex/MeyerK    11/07/26    Add GeoWorks-style module header.
#
# DESCRIPTION:
#     Enable shared PrintCom assembly sources and the PRINT protocol.
#     Use standard PC/GEOS printer-driver build rules.
#
##############################################################################

.PATH.asm .PATH.def: ../PrintCom $(INSTALL_DIR:H)/PrintCom
-IFLAGS += -I../PrintCom -I$(INSTALL_DIR:H)/PrintCom
PROTOCONST = PRINT
#include <$(SYSMAKEFILE)>
