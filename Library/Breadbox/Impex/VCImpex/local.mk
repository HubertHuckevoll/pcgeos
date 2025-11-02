#include <$(SYSMAKEFILE)>

# The manual says I should do this... ;-)
GOCFLAGS += -L vcimpex

_PROTO = 4.0


# Tell the compiler we're doing a library (observe SS!=DS)
# ...not true for Watcom anymore!
#XCCOMFLAGS = -WDE

# Set Copyright notice
#XLINKFLAGS = -N Copyright\20Marcus\20Groeber

# compile user interface metafile into UI file
#vcimpex.ui: vcimpex\vcimpex.pvg
#	pmvg -u -c $(.ALLSRC) $(.TARGET)