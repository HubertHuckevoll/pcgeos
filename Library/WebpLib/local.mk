# Glue resolves C static functions correctly when C objects precede ESP.
OBJS := $(OBJS:Nwebpfilter.obj) webpfilter.obj
EOBJS := $(EOBJS:Nwebpfilter.eobj) webpfilter.eobj
GOBJS := $(GOBJS:Nwebpfilter.gobj) webpfilter.gobj

#include <$(SYSMAKEFILE)>

XCCOMFLAGS += -zu
