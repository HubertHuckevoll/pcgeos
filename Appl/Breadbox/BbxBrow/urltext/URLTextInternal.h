/* Existing declarations shared by URLText source subsystems. */
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
