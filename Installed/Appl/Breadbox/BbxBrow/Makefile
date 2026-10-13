#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = bbxbrow
ASMTOOLS        = asmtoolsManager.asm
HTMLVIEW        = HTMLViewNavigation.goc HTMLViewOptions.goc\
                  HTMLViewOperation.goc HTMLViewStatus.goc URLLoad.goc\
                  GraphicImport.goc AutoBrowse.goc Scrapbook.goc\
                  HTMLView.goc AllocWatcher.goc GlobeAnimation.goc\
                  StatusText.goc HTMLViewLifecycle.goc
INIT            = INIT.goc
NAVIGATE        = BOOKCLAS.goc FAVORCLS.goc BOOKMARK.goc FAVORITE.goc\
                  NAVCACHE.goc NavigationMime.goc Navigation.goc
URLDOC          = URLDOC.goc URLDocumentHistory.goc\
                  URLDocumentNavigation.goc URLDocumentLocalPage.goc
URLDOCCT        = URLDOCCT.goc
URLFETCH        = URLFETCH.goc
URLFRAME        = URLFrameTree.goc URLFrameNavigation.goc\
                  URLFrameScript.goc URLFramePage.goc URLFrameFetch.goc\
                  URLFrame.goc
URLTEXT         = MemStream.c MemStream.h URLTextInternal.h\
                  URLTextClipboard.goc URLTextImageProgress.goc\
                  URLTextImages.goc URLTextLinks.goc URLTextPrint.goc\
                  URLTextScript.goc URLText.goc
UI_TO_RDFS      =
OBJS            = HTMLViewNavigation.obj HTMLViewOptions.obj\
                  HTMLViewOperation.obj HTMLViewStatus.obj URLLoad.obj\
                  GraphicImport.obj AutoBrowse.obj Scrapbook.obj\
                  HTMLView.obj AllocWatcher.obj GlobeAnimation.obj\
                  StatusText.obj HTMLViewLifecycle.obj INIT.obj\
                  BOOKCLAS.obj FAVORCLS.obj BOOKMARK.obj FAVORITE.obj\
                  NAVCACHE.obj NavigationMime.obj Navigation.obj URLDOC.obj\
                  URLDocumentHistory.obj URLDocumentNavigation.obj\
                  URLDocumentLocalPage.obj URLDOCCT.obj URLFETCH.obj\
                  URLFrameTree.obj URLFrameNavigation.obj\
                  URLFrameScript.obj URLFramePage.obj URLFrameFetch.obj\
                  URLFrame.obj MemStream.obj URLTextClipboard.obj\
                  URLTextImageProgress.obj URLTextImages.obj\
                  URLTextLinks.obj URLTextPrint.obj URLTextScript.obj\
                  URLText.obj
COMMON          = bookclas.goh bookmark.goh favorcls.goh favorite.goh\
                  glbanim.goh javascr.h prodgpc.goh prodndo.goh\
                  stattext.goh htmlv_ui.goh htmlview.goh importg.goh\
                  options.goh prodbbx.goh urlfetch.goh
MODULES         = ASMTOOLS
CMODULES        = htmlview init navigate urldoc urldocct urlfetch urlframe\
                  urltext
SRCS            = $(ASMTOOLS) $(HTMLVIEW) $(INIT) $(NAVIGATE) $(URLDOC)\
                  $(URLDOCCT) $(URLFETCH) $(URLFRAME) $(URLTEXT) $(COMMON)
LOBJS           =

PRODUCTS        = AB DBCS ABDBCS 

SYSMAKEFILE     = geode.mk

#include <geos.mk>
#include <gpath.mk>

#if exists(local.mk)
#include "local.mk"
#else
#include <$(SYSMAKEFILE)>
#endif

#if exists($(DEPFILE))
#include "$(DEPFILE)"
#endif

#if exists(AB/$(DEPFILE))
#include "AB/$(DEPFILE)"
#endif

#if exists(DBCS/$(DEPFILE))
#include "DBCS/$(DEPFILE)"
#endif

#if exists(ABDBCS/$(DEPFILE))
#include "ABDBCS/$(DEPFILE)"
#endif
