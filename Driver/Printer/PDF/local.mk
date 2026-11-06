.PATH.asm .PATH.def: ../PrintCom $(INSTALL_DIR:H)/PrintCom
-IFLAGS += -I../PrintCom -I$(INSTALL_DIR:H)/PrintCom
PROTOCONST = PRINT
#include <$(SYSMAKEFILE)>
