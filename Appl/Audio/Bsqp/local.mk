#include <$(SYSMAKEFILE)>

# The globals module has no code. Reuse an existing code segment.
XCCOMFLAGS += $(.TARGET:Mbsqp.*:S|$(.TARGET)|-ntprocess_TEXT|)
