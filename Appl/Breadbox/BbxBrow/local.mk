#include <$(SYSMAKEFILE)>

COMPILE_OPTIONS ?=

# for GEOS2
COMPILE_OPTIONS += -DCOMPILE_OPTION_BOOKMARKS
# for GEOS3+
#COMPILE_OPTIONS += -DCOMPILE_OPTION_FAVORITES
COMPILE_OPTIONS += -DGLOBAL_INTERNET_BUILD
#COMPILE_OPTIONS += -DCOMPILE_OPTION_PROFILING_ON

COMPILE_OPTIONS += $(.TARGET:X\\[AB\\]/*:S|AB| -DCOMPILE_OPTION_AUTO_BROWSE |g)
COMPILE_OPTIONS += $(.TARGET:X\\[JS\\]/*:S|JS| -DJAVASCRIPT_SUPPORT |g)
COMPILE_OPTIONS += $(.TARGET:X\\[JSAB\\]/*:S|JSAB| -DJAVASCRIPT_SUPPORT -DCOMPILE_OPTION_AUTO_BROWSE |g)
COMPILE_OPTIONS += $(.TARGET:X\\[ABDBCS\\]/*:S|ABDBCS| -DCOMPILE_OPTION_AUTO_BROWSE |g)
COMPILE_OPTIONS += $(.TARGET:X\\[JSDBCS\\]/*:S|JSDBCS| -DJAVASCRIPT_SUPPORT |g)
COMPILE_OPTIONS += $(.TARGET:X\\[JSABDBCS\\]/*:S|JSABDBCS| -DJAVASCRIPT_SUPPORT -DCOMPILE_OPTION_AUTO_BROWSE |g)

XGOCFLAGS += $(COMPILE_OPTIONS)
GOCFLAGS += $(COMPILE_OPTIONS)

# -d:  Merge duplicate strings
# -dc: Move strings to code segment
# -Z:  suppress register reloads
# -Os: favor size of execution speed
# JavaScript code uses #if rather than #ifdef
#XCCOMFLAGS = -d -dc -Z -Os -O $(COMPILE_OPTIONS:S|JAVASCRIPT_SUPPORT|JAVASCRIPT_SUPPORT=1|g)
XCCOMFLAGS = $(COMPILE_OPTIONS:S|JAVASCRIPT_SUPPORT|JAVASCRIPT_SUPPORT=1|g)

# -N:  Add stack probes to every routine (only for EC builds)
#ifndef NO_EC
#  XCCOMFLAGS += -N
#endif

# Allow for easy including of JS header files
CCOMFLAGS       += -i="$(CINCLUDE_DIR)/JS"

# Set Copyright notice
#XLINKFLAGS = -N (C)98\20Breadbox\20Computer\20Company $(COMPILE_OPTIONS)
XLINKFLAGS = $(COMPILE_OPTIONS)

full	:: AB JS JSAB
