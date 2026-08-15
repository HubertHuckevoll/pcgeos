#
# Only regular SBCS NC and EC builds are supported by default. pmake
# command-line variables override this assignment, so unsupported variants
# remain available with, for example, pmake "PRODUCTS=JS" full.
#
PRODUCTS =

#include <$(SYSMAKEFILE)>

#
# Regular and DBCS builds exclude JavaScript and AutoBrowse support.
# JS/JSDBCS and AB/ABDBCS builds enable their respective features.
# Keep caller-supplied COMPILE_OPTIONS separate because pmake command-line
# variables cannot be appended to by a makefile.
#
COMPILE_OPTIONS ?=
_HTML4PAR_OPTIONS := $(COMPILE_OPTIONS)
_HTML4PAR_OPTIONS += $(.TARGET:X\\[JS\\]/*:S|JS| -DJAVASCRIPT_SUPPORT |g)
_HTML4PAR_OPTIONS += $(.TARGET:X\\[JSDBCS\\]/*:S|JSDBCS| -DJAVASCRIPT_SUPPORT |g)
_HTML4PAR_OPTIONS += $(.TARGET:X\\[AB\\]/*:S|AB| -DCOMPILE_OPTION_AUTO_BROWSE |g)
_HTML4PAR_OPTIONS += $(.TARGET:X\\[ABDBCS\\]/*:S|ABDBCS| -DCOMPILE_OPTION_AUTO_BROWSE |g)

GOCFLAGS += $(_HTML4PAR_OPTIONS)
CCOMFLAGS += $(_HTML4PAR_OPTIONS:S|JAVASCRIPT_SUPPORT|JAVASCRIPT_SUPPORT=1|g)
LINKFLAGS += $(_HTML4PAR_OPTIONS)
