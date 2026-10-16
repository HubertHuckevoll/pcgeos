/*
 * Private link between URLText image requests and progressive callbacks.
 *
 * URLTextRequestGraphic is stored as fetch extra data. It identifies the
 * image and URL token, records cache policy and the page generation, and
 * marks a canceled stream handoff so acknowledgement cleans up exactly once.
 * URLTextImages.goc and URLTextImageProgress.goc share it. The remaining
 * prototypes connect image MIME fallback and optional AutoBrowse diagnostics.
 * Include after htmlview.goh and importg.goh.
 */
#ifndef _URLTEXT_INTERNAL_H_
#define _URLTEXT_INTERNAL_H_

typedef struct {
    word index;
    NameToken nameT;
    dword imageGeneration;
    Boolean objCache;
    Boolean progressCanceled;
} URLTextRequestGraphic;

void AssumeGraphic(TCHAR *mimeType);

word _pascal _export LoadGraphicProgressCallback(_LoadProgressParams_,
    LoadProgressCallbackType callbackType, void *buffer, word bufSize);

#ifdef COMPILE_OPTION_AUTO_BROWSE
void ShowJSAnalysis(URLTextInstance *pself, VMFileHandle vmf, VMChain vmc);
#endif

#endif
