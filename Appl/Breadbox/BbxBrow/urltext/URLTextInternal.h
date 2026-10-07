/* Existing declarations shared by URLText source subsystems. */
#ifndef _URLTEXT_INTERNAL_H_
#define _URLTEXT_INTERNAL_H_

typedef struct {
    word index;
    NameToken nameT;
    dword imageGeneration;
    Boolean objCache;
#if PROGRESS_DISPLAY
    Boolean progressCanceled;
#endif
} URLTextRequestGraphic;

void AssumeGraphic(TCHAR *mimeType);

#if PROGRESS_DISPLAY
word _pascal _export LoadGraphicProgressCallback(_LoadProgressParams_,
    LoadProgressCallbackType callbackType, void *buffer, word bufSize);
#endif

#ifdef COMPILE_OPTION_AUTO_BROWSE
void ShowJSAnalysis(URLTextInstance *pself, VMFileHandle vmf, VMChain vmc);
#endif

#endif
