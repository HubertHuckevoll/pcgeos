#
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY.
#
# If you edit it, you will lose your changes, should it be regenerated.
#
GEODE           = bbxbrow
ASMTOOLS        = asmtoolsManager.asm
HTMLVIEW        = HTMLViewNavigation.goc HTMLViewOptions.goc\
                  HTMLViewOperation.goc HTMLViewStatus.goc AutoBrowse.goc\
                  Scrapbook.goc HTMLView.goc AllocWatcher.goc\
                  GlobeAnimation.goc HTMLViewLifecycle.goc PortalEmail.goc\
                  StatusText.goc
INIT            = Init.goc
URLDOC          = URLDocumentHistory.goc URLDocumentNavigation.goc\
                  URLDocumentLocalPage.goc URLDocument.goc
URLDOCCT        = URLDocumentControl.goc
URLFETCH        = URLSupport.goc URLLoad.goc URLFetchEngine.goc
URLFRAME        = URLFrameTree.goc URLFrameNavigation.goc\
                  URLFrameScript.goc URLFramePage.goc URLFrameFetch.goc\
                  URLFrame.goc URLFrameGeometry.goc URLFrameTimers.goc
URLTEXT         = MemStream.c MemStream.h URLTextInternal.h\
                  URLTextClipboard.goc URLTextImageProgress.goc\
                  URLTextLinks.goc URLTextPrint.goc URLTextScript.goc\
                  URLText.goc URLTextImages.goc
FAVORITES       = FavoritesDialog.goc FavoritesCreate.goc\
                  FavoritesStore.goc
BOOKMARKS       = BookmarksDialog.goc BookmarksStore.goc
CACHE           = CacheInternal.h SourceCache.goc ObjectCache.goc\
                  CacheLifetime.goc
MIME            = ContentHandling.goc GraphicImport.goc
UI_TO_RDFS      =
OBJS            = HTMLViewNavigation.obj HTMLViewOptions.obj\
                  HTMLViewOperation.obj HTMLViewStatus.obj AutoBrowse.obj\
                  Scrapbook.obj HTMLView.obj AllocWatcher.obj\
                  GlobeAnimation.obj HTMLViewLifecycle.obj PortalEmail.obj\
                  StatusText.obj Init.obj URLDocumentHistory.obj\
                  URLDocumentNavigation.obj URLDocumentLocalPage.obj\
                  URLDocument.obj URLDocumentControl.obj URLSupport.obj\
                  URLLoad.obj URLFetchEngine.obj URLFrameTree.obj\
                  URLFrameNavigation.obj URLFrameScript.obj\
                  URLFramePage.obj URLFrameFetch.obj URLFrame.obj\
                  URLFrameGeometry.obj URLFrameTimers.obj MemStream.obj\
                  URLTextClipboard.obj URLTextImageProgress.obj\
                  URLTextLinks.obj URLTextPrint.obj URLTextScript.obj\
                  URLText.obj URLTextImages.obj FavoritesDialog.obj\
                  FavoritesCreate.obj FavoritesStore.obj\
                  BookmarksDialog.obj BookmarksStore.obj SourceCache.obj\
                  ObjectCache.obj CacheLifetime.obj ContentHandling.obj\
                  GraphicImport.obj
COMMON          = bookclas.goh bookmark.goh favorcls.goh favorite.goh\
                  glbanim.goh javascr.h prodgpc.goh prodndo.goh\
                  stattext.goh htmlv_ui.goh htmlview.goh importg.goh\
                  options.goh prodbbx.goh urlfetch.goh
MODULES         = ASMTOOLS
CMODULES        = htmlview init urldoc urldocct urlfetch urlframe urltext\
                  favorites bookmarks cache mime
SRCS            = $(ASMTOOLS) $(HTMLVIEW) $(INIT) $(URLDOC) $(URLDOCCT)\
                  $(URLFETCH) $(URLFRAME) $(URLTEXT) $(FAVORITES)\
                  $(BOOKMARKS) $(CACHE) $(MIME) $(COMMON)
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
