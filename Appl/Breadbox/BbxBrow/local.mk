#
# mkmf finds product directories by their is_a_product marker and records
# them in the generated Makefile's PRODUCTS variable. Keep that list
# available for explicit builds, but clear it before geode.mk so the
# products do not become dependencies of the default full target.
# Override this default on the command line, for example:
#     pmake "PRODUCTS=DBCS AB ABDBCS" full
#
PRODUCTS =

# BbxBrow's regular build is SBCS with neither JavaScript nor AutoBrowse.
# DBCS changes character mode only. AB enables COMPILE_OPTION_AUTO_BROWSE;
# ABDBCS enables it together with DBCS. JavaScript or AutoBrowse causes the
# matching Html4Par build to derive HTML_SCRIPT_SUPPORT.
#
# Glue file-local lookup needs Images to establish the shared URLTEXT_TEXT segment.
OBJS := URLTextImages.obj $(OBJS:NURLTextImages.obj)
EOBJS := URLTextImages.eobj $(EOBJS:NURLTextImages.eobj)
GOBJS := URLTextImages.gobj $(GOBJS:NURLTextImages.gobj)

#include <$(SYSMAKEFILE)>

COMPILE_OPTIONS ?=
#COMPILE_OPTIONS += -DCOMPILE_OPTION_BOOKMARKS
COMPILE_OPTIONS += -DCOMPILE_OPTION_FAVORITES
COMPILE_OPTIONS += -DGLOBAL_INTERNET_BUILD
#COMPILE_OPTIONS += -DCOMPILE_OPTION_PROFILING_ON

COMPILE_OPTIONS += $(.TARGET:X\\[AB\\]/*:S|AB| -DCOMPILE_OPTION_AUTO_BROWSE |g)
COMPILE_OPTIONS += $(.TARGET:X\\[ABDBCS\\]/*:S|ABDBCS| -DCOMPILE_OPTION_AUTO_BROWSE |g)

XGOCFLAGS += $(COMPILE_OPTIONS)
GOCFLAGS += $(COMPILE_OPTIONS)

# -d:  Merge duplicate strings
# -dc: Move strings to code segment
# -Z:  suppress register reloads
# -Os: favor size of execution speed
# JavaScript code uses #if rather than #ifdef
#XCCOMFLAGS = -d -dc -Z -Os -O $(COMPILE_OPTIONS:S|JAVASCRIPT_SUPPORT|JAVASCRIPT_SUPPORT=1|g)
XCCOMFLAGS = -zu $(COMPILE_OPTIONS:S|JAVASCRIPT_SUPPORT|JAVASCRIPT_SUPPORT=1|g)
# removed -zc because it is not compatible with code_seg() pragma

# Match compiler defaults to the source pragmas; avoid unused filename segments.
#if !empty(CCOM:M*wcc*)
XCCOMFLAGS += $(.TARGET:T:R:MMemStream:S|MemStream|-nt=URLTEXT_TEXT|) \
             $(.TARGET:T:R:MURLTextImages:S|URLTextImages|-nt=URLTEXT_TEXT|) \
             $(.TARGET:T:R:MURLTextImageProgress:S|URLTextImageProgress|-nt=URLTEXT_TEXT|) \
             $(.TARGET:T:R:MURLTextLinks:S|URLTextLinks|-nt=URLTEXT_TEXT|) \
             $(.TARGET:T:R:MURLTextPrint:S|URLTextPrint|-nt=URLTEXT_TEXT|) \
             $(.TARGET:T:R:MURLTextScript:S|URLTextScript|-nt=URLTEXT_TEXT|) \
             $(.TARGET:T:R:MURLTextClipboard:S|URLTextClipboard|-nt=URLTEXT2_TEXT|)
#endif

# -N:  Add stack probes to every routine (only for EC builds)
#ifndef NO_EC
#  XCCOMFLAGS += -N
#endif

# Set Copyright notice
#XLINKFLAGS = -N (C)98\20Breadbox\20Computer\20Company $(COMPILE_OPTIONS)
XLINKFLAGS = $(COMPILE_OPTIONS)
