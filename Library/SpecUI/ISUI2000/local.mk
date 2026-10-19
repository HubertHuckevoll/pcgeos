# ISUI 2000 shares ISUI behaviour and sources; appearance is opt-in.
PCTAGSFLAGS += -c
PROTOCONST = SPUI
ASMFLAGS += -DISUI2000 -wprivate -wunref -wunref_local
UICFLAGS += -DISUI2000
LIBNAME = spui
UI_TO_RDFS = cmainManager.ui cspecCUAS.ui

ISUI_MODULES = Button Comp Gadget Item Main Spec Utils View Win

#include <$(SYSMAKEFILE)>

ISUI_SOURCE_PATHS = $(INSTALL_DIR:H)/CommonUI \
    $(ISUI_MODULES:S|^|$(INSTALL_DIR:H)/CommonUI/C|g) \
    $(INSTALL_DIR:H)/ISUI/Win $(INSTALL_DIR:H)/ISUI/View

.PATH.asm : $(ISUI_SOURCE_PATHS)
.PATH.def : $(ISUI_SOURCE_PATHS)
.PATH.ui : $(ISUI_SOURCE_PATHS)
-IFLAGS += -I$(INSTALL_DIR:H)/CommonUI \
    -I$(INSTALL_DIR:H)/CommonUI/C$(.TARGET:R:T) \
    -I$(INSTALL_DIR:H)/ISUI/Win -I$(INSTALL_DIR:H)/ISUI/View
DEPFLAGS += -I$(INSTALL_DIR:H)/CommonUI \
    -I$(INSTALL_DIR:H)/CommonUI/C$bi \
    -I$(INSTALL_DIR:H)/ISUI/Win -I$(INSTALL_DIR:H)/ISUI/View
LINKFLAGS += -nll -f
