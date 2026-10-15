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
COMPILE_OPTIONS ?=
#COMPILE_OPTIONS += -DCOMPILE_OPTION_BOOKMARKS
COMPILE_OPTIONS += -DCOMPILE_OPTION_FAVORITES
#COMPILE_OPTIONS += -DCOMPILE_OPTION_PROFILING_ON
#COMPILE_OPTIONS += -DEMAIL_ACCT_CMD

COMPILE_OPTIONS += $(.TARGET:X\\[AB\\]/*:S|AB| -DCOMPILE_OPTION_AUTO_BROWSE |g)
COMPILE_OPTIONS += $(.TARGET:X\\[ABDBCS\\]/*:S|ABDBCS| -DCOMPILE_OPTION_AUTO_BROWSE |g)

#include <$(SYSMAKEFILE)>

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
XCCOMFLAGS += $(.TARGET:T:R:MHTMLView:S|HTMLView|-nt=HTMLVIEW_TEXT|) \
             $(.TARGET:T:R:MHTMLViewNavigation:S|HTMLViewNavigation|-nt=UIAction_TEXT|) \
             $(.TARGET:T:R:MHTMLViewOptions:S|HTMLViewOptions|-nt=UIRare_TEXT|) \
             $(.TARGET:T:R:MHTMLViewOperation:S|HTMLViewOperation|-nt=UIRare_TEXT|) \
             $(.TARGET:T:R:MHTMLViewStatus:S|HTMLViewStatus|-nt=UIOften_TEXT|) \
             $(.TARGET:T:R:MHTMLViewLifecycle:S|HTMLViewLifecycle|-nt=OpenClos_TEXT|) \
             $(.TARGET:T:R:MAutoBrowse:S|AutoBrowse|-nt=scrapbk_TEXT|) \
             $(.TARGET:T:R:MScrapbook:S|Scrapbook|-nt=scrapbk_TEXT|) \
             $(.TARGET:T:R:MURLLoad:S|URLLoad|-nt=LoadURL_TEXT|) \
             $(.TARGET:T:R:MGraphicImport:S|GraphicImport|-nt=ImportG_TEXT|) \
             $(.TARGET:T:R:MStatusText:S|StatusText|-nt=StatText_TEXT|) \
             $(.TARGET:T:R:MGlobeAnimation:S|GlobeAnimation|-nt=GLBANIM_TEXT|) \
             $(.TARGET:T:R:MAllocWatcher:S|AllocWatcher|-nt=AWATCHER_TEXT|) \
             $(.TARGET:T:R:MContentHandling:S|ContentHandling|-nt=Navigation_TEXT|) \
             $(.TARGET:T:R:MURLSupport:S|URLSupport|-nt=Navigation_TEXT|) \
             $(.TARGET:T:R:MPortalEmail:S|PortalEmail|-nt=Navigation_TEXT|) \
             $(.TARGET:T:R:MBookmarksDialog:S|BookmarksDialog|-nt=BOOKCLAS_TEXT|) \
             $(.TARGET:T:R:MBookmarksStore:S|BookmarksStore|-nt=BOOKMARK_TEXT|) \
             $(.TARGET:T:R:MFavoritesDialog:S|FavoritesDialog|-nt=FAVORCLS_TEXT|) \
             $(.TARGET:T:R:MFavoritesCreate:S|FavoritesCreate|-nt=FAVORCLS_TEXT|) \
             $(.TARGET:T:R:MFavoritesStore:S|FavoritesStore|-nt=FAVORITE_TEXT|) \
             $(.TARGET:T:R:MInit:S|Init|-nt=Init_TEXT|) \
             $(.TARGET:T:R:MURLDocument:S|URLDocument|-nt=URLDocument_TEXT|) \
             $(.TARGET:T:R:MURLDocumentControl:S|URLDocumentControl|-nt=URLDocumentControl_TEXT|) \
             $(.TARGET:T:R:MURLFetchEngine:S|URLFetchEngine|-nt=URLFetchEngine_TEXT|) \
             $(.TARGET:T:R:MCacheLifetime:S|CacheLifetime|-nt=Init_TEXT|) \
             $(.TARGET:T:R:MSourceCache:S|SourceCache|-nt=NAVCACHE_TEXT|) \
             $(.TARGET:T:R:MObjectCache:S|ObjectCache|-nt=NAVCACHE_TEXT|) \
             $(.TARGET:T:R:MMemStream:S|MemStream|-nt=URLText_TEXT|) \
             $(.TARGET:T:R:MURLTextImages:S|URLTextImages|-nt=URLText_TEXT|) \
             $(.TARGET:T:R:MURLTextImageProgress:S|URLTextImageProgress|-nt=URLText_TEXT|) \
             $(.TARGET:T:R:MURLTextLinks:S|URLTextLinks|-nt=URLText_TEXT|) \
             $(.TARGET:T:R:MURLTextPrint:S|URLTextPrint|-nt=URLText_TEXT|) \
             $(.TARGET:T:R:MURLTextScript:S|URLTextScript|-nt=URLText_TEXT|) \
             $(.TARGET:T:R:MURLTextClipboard:S|URLTextClipboard|-nt=URLTEXT2_TEXT|) \
             $(.TARGET:T:R:MURLFrameFetch:S|URLFrameFetch|-nt=FRFETCH_TEXT|) \
             $(.TARGET:T:R:MURLFrameTree:S|URLFrameTree|-nt=URLFrame_TEXT|) \
             $(.TARGET:T:R:MURLFrameNavigation:S|URLFrameNavigation|-nt=URLFrame_TEXT|) \
             $(.TARGET:T:R:MURLFrameScript:S|URLFrameScript|-nt=URLFrame_TEXT|) \
             $(.TARGET:T:R:MURLFrameTimers:S|URLFrameTimers|-nt=URLFrame_TEXT|) \
             $(.TARGET:T:R:MURLFramePage:S|URLFramePage|-nt=FRFETCH3_TEXT|) \
             $(.TARGET:T:R:MURLFrameGeometry:S|URLFrameGeometry|-nt=FRFETCH3_TEXT|) \
             $(.TARGET:T:R:MURLDocumentHistory:S|URLDocumentHistory|-nt=URLDocument_TEXT|) \
             $(.TARGET:T:R:MURLDocumentNavigation:S|URLDocumentNavigation|-nt=URLDocument_TEXT|) \
             $(.TARGET:T:R:MURLDocumentLocalPage:S|URLDocumentLocalPage|-nt=LOCALPAG_TEXT|)
#endif

# -N:  Add stack probes to every routine (only for EC builds)
#ifndef NO_EC
#  XCCOMFLAGS += -N
#endif

# Set Copyright notice
#XLINKFLAGS = -N (C)98\20Breadbox\20Computer\20Company $(COMPILE_OPTIONS)
XLINKFLAGS = $(COMPILE_OPTIONS)
