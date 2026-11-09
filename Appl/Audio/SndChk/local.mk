#include <$(SYSMAKEFILE)>

# These modules contain only data and objects. Reuse a live code segment.
XCCOMFLAGS += $(.TARGET:Mglobals.*:S|$(.TARGET)|-ntprocess_TEXT|)
XCCOMFLAGS += $(.TARGET:Muimain.*:S|$(.TARGET)|-ntprocess_TEXT|)
