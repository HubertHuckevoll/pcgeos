#include <$(SYSMAKEFILE)>

# The manual says I should do this... ;-)
XGOCFLAGS = -L vcimpex

# Tell the compiler we're doing a library (observe SS!=DS)
# ...not true for Watcom anymore! put "_pascal _export" on
# the declaration and the implementation signature instead.
#XCCOMFLAGS = -WDE

# Set Copyright notice
#XLINKFLAGS = -N Copyright\20Marcus\20Groeber

# compile user interface metafile into UI file
#vcimpex.ui: vcimpex\vcimpex.pvg
#	pmvg -u -c $(.ALLSRC) $(.TARGET)