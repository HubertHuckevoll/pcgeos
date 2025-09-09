#include <$(SYSMAKEFILE)>

# The manual says I should do this... ;-)
XGOCFLAGS = -L meta

# Turn on/off logging
XCCOMFLAGS += -DDEBUG_LOG

# Set Copyright notice
# XLINKFLAGS = -N Copyright\20Marcus\20Groeber