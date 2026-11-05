#!/usr/bin/env perl
# Run production folder/worker/tag code on the host. Author: Codex/MeyerK
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Temp qw(tempdir);
my $app = abs_path(dirname(__FILE__).'/..');
my $tmp = tempdir('bsqp-folder-XXXXXX', TMPDIR=>1, CLEANUP=>!$ENV{KEEP_TESTS});
sub read_file { open my $f, '<', $_[0] or die $!; local $/; return <$f>; }
my $folder = read_file("$app/Main/folder.goc");
my $tags = read_file("$app/Main/tags.goc");
my $header = read_file("$app/Main/bsqp.goh");
my $audio = read_file("$app/Main/subcode.goc");
for ($folder, $tags, $header, $audio) { s/\r\n/\n/g; }
$header =~ s{//([^\n]*)}{/*$1*/}g;
$header =~ s/^#include[^\n]*\n//mg;
my $chars = read_file("$app/../../../CInclude/char.h");
my %needed = map { $_ => 1 } $tags =~ /\b(C_\w+)\b/g;
while ($chars =~ /^(#define (C_\w+)[^\r\n]*)/mg) {
    $header .= "$1\n" if $needed{$2};
}
for my $name (qw(BQ_StartPlay BQ_PlayThread)) {
    $audio =~ /^([^\n;{}]*\b$name\s*\([^;]*?\)\n\{.*?^\})/ms or die "missing $name";
    $folder .= "$1\n";
}
my %methods = (
    MSG_BSQP_LOAD_FOLDER => 'MemHandle requestH',
    MSG_BSQP_SCAN_FOLDER => 'dword generation',
    MSG_BSQP_READ_TAGS => 'dword generation',
    MSG_BSQP_TRACK_MONIKER => 'optr list, word item',
    MSG_BSQP_TRACK_ACTIVATE => 'word selection, word numSelections, word stateFlags',
);
for ($folder, $tags) {
    s/^\@include[^\n]*\n//mg;
    s/^#include[^\n]*\n//mg;
    s/\@extern method BSQPProcessClass, (\w+)/static void $1($methods{$1})/g;
    s/\@(?:send(?:, forceQueue)?|call) process::MSG_PROCESS_BSQP_FINISHED/QueueFinished/g;
    s/\@send, forceQueue process::MSG_BSQP_SCAN_FOLDER/QueueScan/g;
    s/\@send, forceQueue process::MSG_BSQP_READ_TAGS/QueueTags/g;
    s/\@send, forceQueue process::MSG_BSQP_TRACK_MONIKER/QueueRow/g;
    s/\@(?:call|send) (\w+)::(\w+)/UI_$1_$2/g;
    s/\@TrackList/123/g;
    die 'unhandled GOC' if /\@/;
}
open my $out, '>', "$tmp/check.c" or die $!;
print $out <<'C';
#include <assert.h>
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef uint8_t byte;
typedef uint16_t word;
typedef uint32_t dword;
typedef word MemHandle, DiskHandle, VMBlockHandle, VMFileHandle, FileHandle;
typedef word TimerHandle, WindowHandle, Color;
typedef byte FileAttrs;
typedef int Boolean;
typedef dword optr;
typedef char PathName[198], FileLongName[36];
#define _pascal
#define TRUE 1
#define FALSE 0
#define HF_DYNAMIC 0
#define HAF_ZERO_INIT 1
#define MGIT_SIZE 0
#define SP_PRIVATE_DATA 1
#define SP_DOCUMENT 3
#define VMAF_FORCE_READ_WRITE 0
#define VMAF_FORCE_DENY_WRITE 0
#define VMO_TEMP_FILE 1
#define VM_UPDATE_NOTHING_DIRTY 272
#define FILE_POS_START 0
#define FRSPF_ADD_DRIVE_NAME 2
#define FILE_ACCESS_R 0
#define FILE_DENY_W 0
#define FILE_DENY_NONE 0
#define FEA_NAME 1
#define FEA_END_OF_LIST 0
#define FESRT_NAME 2
#define FILE_ENUM_ALL_FILE_TYPES 0x70
#define FESF_CALLBACK 4
#define PRIORITY_HIGH 0
#define VUM_NOW 0
#define CODE_PAGE_LATIN_1 819
#define BSNW_STATUS_OK 0
#define BSNW_ABORT 9
#define BSNW_MEMORY_ERROR 4
#define BSNW_TIMEOUT 8
#define BSNW_TEST_ONLY 1
C
print $out "$header\n";
print $out <<'C';
char fullPath[BQ_FULL_PATH_SIZE], globalText[80];
char playText[] = "PLAY", pauseText[] = "PAUSE";
TimerHandle tih;
word tid, playFlag, rmsValue, bqChannels, bqBits, bqOptions, bqDispStyle;
dword bqPlaySerial, bqWorkerSerial, bqSampleRate, bqAllBytes, bqSampleBytes;
Boolean bqStopRequested;
WindowHandle winHan;
Color backGroundColor;
static dword ticks;
static int errors, lastError, starts, fileCloses, fileOwned, maxWorkers;
static int failAlloc, failOpen, failThread, failEnum, failVM, probeResult, playResult;
static int dirDepth, vmOpen, deleted;
static word selected = BQ_NO_TRACK;
static char button[10], folderLabel[256];
static byte audioBytes[40000];
static dword audioLength, audioPosition, bytesRead;
static int shortRead, failSeek;
static void *memory[64];
static word memorySize[64];
static int memoryCount;
static MemHandle MemAlloc(word size, word flags, word zero)
{
    word i;
    (void)flags; assert(zero == HAF_ZERO_INIT);
    if (failAlloc) return 0;
    for (i=1; i<64 && memory[i]; ++i) { }
    assert(i<64); memory[i] = calloc(1, size); assert(memory[i]);
    memorySize[i] = size; ++memoryCount; return i;
}
static void *MemLock(MemHandle handle) { assert(handle && memory[handle]); return memory[handle]; }
static void MemUnlock(MemHandle handle) { assert(handle && memory[handle]); }
static void MemFree(MemHandle handle) { assert(memory[handle]); free(memory[handle]); memory[handle]=0; --memoryCount; }
static word MemGetInfo(MemHandle handle, word type) { (void)type; return memorySize[handle]; }
typedef struct { DiskHandle ALB_diskHandle; PathName ALB_path; FileLongName ALB_dataFile; } AppLaunchBlock;
typedef struct { BQTrack *data; word count; } HostArray;
static HostArray arrays[8];
static int arrayLocks;
static VMFileHandle VMOpen(char *nameP, word flags, word mode, word compression)
{
    (void)flags; (void)compression; assert(mode == VMO_TEMP_FILE && !vmOpen);
    strcat(nameP, "\\bsqp.tmp"); vmOpen = 1; return 1;
}
static word VMUpdate(VMFileHandle fileH) { assert(fileH==1); return failVM ? 273 : 0; }
static VMBlockHandle HugeArrayCreate(VMFileHandle fileH, word size, word header)
{
    word i;
    assert(fileH==1 && size==sizeof(BQTrack) && !header);
    for (i=1; i<8 && arrays[i].data; ++i) { }
    assert(i<8); arrays[i].data=calloc(1, sizeof(BQTrack)); return i;
}
static void HugeArrayDestroy(VMFileHandle fileH, VMBlockHandle arrayH)
{
    assert(fileH==1 && arrays[arrayH].data && !arrayLocks);
    free(arrays[arrayH].data); arrays[arrayH].data=0; arrays[arrayH].count=0;
}
static dword HugeArrayLock(VMFileHandle fileH, VMBlockHandle arrayH, dword item, void **ptrP, word *sizeP)
{
    assert(fileH==1 && arrays[arrayH].data && item<arrays[arrayH].count);
    *ptrP=&arrays[arrayH].data[item]; *sizeP=sizeof(BQTrack); ++arrayLocks; return 1;
}
static void HugeArrayUnlock(void *ptrP) { assert(ptrP && arrayLocks); --arrayLocks; }
static void HugeArrayDirty(const void *ptrP) { assert(ptrP && arrayLocks); }
static void HugeArrayInsert(VMFileHandle fileH, VMBlockHandle arrayH, word count, dword at, const void *dataP)
{
    HostArray *aP=&arrays[arrayH];
    assert(fileH==1 && count==1 && at<=aP->count && !arrayLocks);
    aP->data=realloc(aP->data, (aP->count+1)*sizeof(BQTrack)); assert(aP->data);
    memmove(aP->data+at+1,aP->data+at,(aP->count-at)*sizeof(BQTrack));
    memcpy(aP->data+at,dataP,sizeof(BQTrack)); ++aP->count;
}
static void HugeArrayReplace(VMFileHandle fileH, VMBlockHandle arrayH, word count, dword at, const void *dataP)
{
    assert(fileH==1 && count==1 && at<arrays[arrayH].count && !arrayLocks);
    memcpy(arrays[arrayH].data+at,dataP,sizeof(BQTrack));
}
static word VMClose(VMFileHandle fileH, Boolean noError)
{
    word i;
    assert(fileH==1 && noError && vmOpen);
    for (i=1;i<8;++i) if (arrays[i].data) HugeArrayDestroy(fileH,i);
    vmOpen=0; return 0;
}
static word FileDelete(const char *nameP) { assert(strstr(nameP,"bsqp.tmp")); ++deleted; return 0; }
static void FilePushDir(void) { ++dirDepth; }
static void FilePopDir(void) { assert(dirDepth); --dirDepth; }
static char currentPath[256];
static DiskHandle FileSetCurrentPath(DiskHandle disk, const char *pathP)
{
    assert(dirDepth);
    if(!strcmp(pathP,"bad")) return 0;
    if(disk==SP_DOCUMENT) {
        strcpy(currentPath,"\\DOCUMENT\\"); strcat(currentPath,pathP);
    } else strcpy(currentPath, disk==SP_PRIVATE_DATA ? "\\PRIVATE" : pathP);
    return 2;
}
static DiskHandle FileResolveStandardPath(char **bufferP,word capacity,const char *tailP,word flags,FileAttrs *attrsP)
{
    assert(dirDepth && !*tailP && flags==FRSPF_ADD_DRIVE_NAME);
    (void)attrsP;
    if(strlen(currentPath)+3>capacity) return 0;
    strcpy(*bufferP,"C:"); strcat(*bufferP,currentPath); *bufferP+=strlen(*bufferP); return 2;
}
static FileHandle FileOpen(const char *nameP, word flags)
{ (void)nameP; (void)flags; if(failOpen) return 0; ++fileOwned; return 55; }
static word FileClose(FileHandle fileH, Boolean noError)
{ assert(fileH==55 && fileOwned && noError); --fileOwned; ++fileCloses; return 0; }
static dword FileSize(FileHandle fileH) { assert(fileH==55); return audioLength; }
static dword FilePos(FileHandle fileH, dword position, word mode)
{ assert(fileH==55 && mode==FILE_POS_START); if(failSeek) return 0xffffffffUL; audioPosition=position; return position; }
static word FileRead(FileHandle fileH, void *destP, word count, word flags)
{
    assert(fileH==55 && !flags);
    if(audioPosition>audioLength) return 0;
    if(count>audioLength-audioPosition) count=(word)(audioLength-audioPosition);
    if(shortRead && count) --count;
    memcpy(destP,audioBytes+audioPosition,count); audioPosition+=count; bytesRead+=count; return count;
}
static int LocalCmpStringsNoCase(const char *aP,const char *bP,word limit)
{
    (void)limit;
    while(*aP && tolower((unsigned char)*aP)==tolower((unsigned char)*bP)) { ++aP; ++bP; }
    return tolower((unsigned char)*aP)-tolower((unsigned char)*bP);
}
static word LocalCodePageToGeosChar(word ch, word page, word fallback)
{
    (void)fallback; assert(page==CODE_PAGE_LATIN_1);
    if(ch==0xfc) return 0x9f;
    if(ch==0xe9) return 0x8e;
    if(ch==0xff) return 0xd8;
    return ch;
}
static dword TimerGetCount(void) { return ticks; }
static void BSNWaveStop(void) { }
static void BSNWaveSetPause(word mode) { assert(mode==2); }
static void RedrawSettings(word state) { (void)state; }
static void RedrawStatus(word state) { (void)state; }
static void RedrawRMS(word state) { (void)state; }
static void RedrawFileName(word state) { (void)state; }
static void RedrawTime(word state) { (void)state; }
static int BQ_Audio(FileHandle fileH, Boolean preview)
{ assert(fileH==55); return preview ? probeResult : bqStopRequested ? BSNW_ABORT : playResult; }
word BQ_PlayThread(word fileH);
void BQ_StartPlay(void);
static int ThreadCreate(word priority, word arg, word (*entryP)(word), word stack, word owner)
{
    (void)priority; (void)owner;
    assert(arg==55 && entryP==BQ_PlayThread && stack==3000 && fileOwned==1);
    if(failThread) return 0;
    ++starts; if(fileOwned>maxWorkers) maxWorkers=fileOwned; return 1;
}
#define GeodeGetProcessHandle() 1
static void UI_PLAYTrigger_MSG_GEN_REPLACE_VIS_MONIKER_TEXT(const char *textP, word mode)
{ (void)mode; assert(!arrayLocks); strcpy(button,textP); }
static void UI_PLAYTrigger_MSG_GEN_SET_ENABLED(word mode) { (void)mode; }
static void UI_PLAYTrigger_MSG_GEN_SET_NOT_ENABLED(word mode) { (void)mode; }
static word UI_TrackList_MSG_GEN_ITEM_GROUP_GET_SELECTION(void) { return selected; }
static void UI_TrackList_MSG_GEN_ITEM_GROUP_SET_SINGLE_SELECTION(word item,Boolean indeterminate)
{ assert(!indeterminate && !arrayLocks); selected=item; }
static void UI_TrackList_MSG_GEN_ITEM_GROUP_MAKE_ITEM_VISIBLE(word item) { assert(item==selected && !arrayLocks); }
static void UI_TrackList_MSG_GEN_DYNAMIC_LIST_INITIALIZE(word count) { (void)count; selected=BQ_NO_TRACK; assert(!arrayLocks); }
static void UI_TrackList_MSG_GEN_DYNAMIC_LIST_REPLACE_ITEM_TEXT(word item,const char *textP)
{ (void)item; assert(!arrayLocks && strlen(textP)<BQ_LABEL_SIZE+3); }
static void UI_BSQPPrimary_MSG_GEN_REPLACE_VIS_MONIKER_TEXT(const char *textP,word mode) { (void)textP; (void)mode; assert(!arrayLocks); }
static void UI_FolderGlyph_MSG_GEN_REPLACE_VIS_MONIKER_TEXT(const char *textP,word mode) { (void)mode; assert(!arrayLocks); strcpy(folderLabel,textP); }
static void UI_EmptyGlyph_MSG_GEN_SET_USABLE(word mode) { (void)mode; }
static void UI_EmptyGlyph_MSG_GEN_SET_NOT_USABLE(word mode) { (void)mode; }
static int UI_WavFileSelector_MSG_GEN_PATH_SET(const char *pathP, DiskHandle disk) { (void)pathP; (void)disk; return 0; }
typedef struct { word attr; void *value; word size; void *name; } FileExtAttrDesc;
typedef struct { const char *nameP; } FileEnumCallbackData;
typedef struct FileEnumParams {
    word FEP_searchFlags; FileExtAttrDesc *FEP_returnAttrs; word FEP_returnSize;
    word FEP_bufSize, FEP_skipCount;
    word (*FEP_callback)(struct FileEnumParams *, FileEnumCallbackData *, word);
    FileExtAttrDesc *FEP_callbackAttrs;
} FileEnumParams;
static char entryNames[700][36];
static word entryCount;
static void *FileEnumLocateAttr(FileEnumCallbackData *dataP, word attr, void *nameP)
{ (void)nameP; assert(attr==FEA_NAME); return (void *)dataP->nameP; }
static word FileEnum(FileEnumParams *paramsP, MemHandle *resultH, word *noFitP)
{
    char *resultP;
    word i, matching, count;
    FileEnumCallbackData data;
    assert(dirDepth && paramsP->FEP_bufSize==32 && paramsP->FEP_returnSize==36);
    if(failEnum) return 0xffff;
    *resultH=MemAlloc(32*36,HF_DYNAMIC,HAF_ZERO_INIT); assert(*resultH);
    resultP=MemLock(*resultH); matching=count=0;
    for(i=0;i<entryCount;++i) {
        if(!strncmp(entryNames[i],"DIR:",4)) continue;
        data.nameP=entryNames[i];
        if(paramsP->FEP_callback(paramsP,&data,0)) {
            if(matching++ < paramsP->FEP_skipCount) continue;
            if(count<32) { strcpy(resultP+count*36,entryNames[i]); ++count; }
        }
    }
    MemUnlock(*resultH);
    *noFitP=matching-paramsP->FEP_skipCount-count;
    return count;
}
typedef struct { int kind, result; dword serial; word item; } Event;
static Event events[20000];
static unsigned eventRead, eventWrite;
static void Queue(int kind,int result,dword serial,word item)
{ assert(eventWrite<20000); events[eventWrite].kind=kind; events[eventWrite].result=result; events[eventWrite].serial=serial; events[eventWrite++].item=item; }
static void QueueFinished(int result,dword serial) { Queue(1,result,serial,0); }
static void QueueScan(dword generation) { Queue(2,0,generation,0); }
static void QueueTags(dword generation) { Queue(3,0,generation,0); }
static void QueueRow(optr list,word item) { assert(list==123); Queue(4,0,0,item); }
C
print $out "$tags\n$folder\n";
print $out <<'C';
static void Pump(void)
{
    Event e;
    while(eventRead<eventWrite) {
        e=events[eventRead++];
        if(e.kind==1) {
            if(BQ_FinishPlayback(e.result,e.serial) && e.result!=BSNW_STATUS_OK && e.result!=BSNW_ABORT) { ++errors; lastError=e.result; }
        } else if(e.kind==2) MSG_BSQP_SCAN_FOLDER(e.serial);
        else if(e.kind==3) MSG_BSQP_READ_TAGS(e.serial);
        else MSG_BSQP_TRACK_MONIKER(123,e.item);
    }
    eventRead=eventWrite=0;
    assert(!dirDepth && !arrayLocks);
}
static MemHandle Request(const char *pathP,const char *nameP)
{
    MemHandle h;
    BQFolderRequest *p;
    h=MemAlloc(sizeof(BQFolderRequest),HF_DYNAMIC,HAF_ZERO_INIT); assert(h);
    p=MemLock(h); p->disk=2; strcpy(p->path,pathP); strcpy(p->file,nameP); MemUnlock(h); return h;
}
static void Complete(void)
{ assert(playFlag && fileOwned==1); BQ_PlayThread(55); Pump(); }
static void CheckTag(const char *pathP,const char *expectedP)
{
    FILE *f;
    struct { byte before[8]; char label[BQ_LABEL_SIZE]; byte after[8]; } guard;
    char *label=guard.label;
    unsigned i;
    int oldMemory;
    f=fopen(pathP,"rb"); assert(f);
    audioLength=(dword)fread(audioBytes,1,sizeof(audioBytes),f); fclose(f);
    memset(&guard,0xa5,sizeof(guard));
    audioPosition=bytesRead=0; strcpy(label,"original.mp3");
    oldMemory=memoryCount; BQ_ReadTags(55,label);
    if(strcmp(label,expectedP)) { fprintf(stderr,"%s: got [%s], expected [%s]\n",pathP,label,expectedP); abort(); }
    assert(memoryCount==oldMemory && bytesRead<=8320);
    for(i=0;i<8;++i) assert(guard.before[i]==0xa5 && guard.after[i]==0xa5);
}
static void CheckFolders(void)
{
    word i, oldArray, oldCount, next, savedCount;
    int before, oldMemory;
    dword serial;
    MemHandle launchH, requestH;
    AppLaunchBlock *launchP;
    FileEnumCallbackData data;
    FileEnumParams params;
    static byte visited[700];
    audioLength=16; memset(audioBytes,0,16);
    entryCount=130;
    for(i=0;i<entryCount;++i) sprintf(entryNames[i],"song%03u.%s",entryCount-i,i%2 ? "mp3" : "WAV");
    strcpy(entryNames[1],"DIR:child.mp3"); strcpy(entryNames[2],"ignore.txt");
    assert(BQ_IsAudio("a.Mp3") && BQ_IsAudio("a.WAV") && !BQ_IsAudio("a.mp3.exe") && !BQ_IsAudio("foo"));
    MSG_BSQP_LOAD_FOLDER(Request("\\music","song060.WAV")); Pump();
    assert(trackCount==128 && starts==1 && playingTrack<trackCount);
    assert(!strcmp(arrays[tracksH].data[playingTrack].name,"song060.WAV"));
    for(i=1;i<trackCount;++i) assert(LocalCmpStringsNoCase(arrays[tracksH].data[i-1].name,arrays[tracksH].data[i].name,0)<0);
    Complete(); assert(!playFlag && !running && playingTrack==BQ_NO_TRACK);
    /* A plain folder open selects the first row and never starts it. */
    before=starts; MSG_BSQP_LOAD_FOLDER(Request("\\","")); Pump();
    assert(starts==before && selected==0 && !strcmp(folderLabel,"C:\\"));
    /* The selector can return a standard-path disk and a relative MUSIC path. */
    requestH=Request("MUSIC","");
    ((BQFolderRequest *)MemLock(requestH))->disk=SP_DOCUMENT;
    MemUnlock(requestH);
    MSG_BSQP_LOAD_FOLDER(requestH); Pump();
    assert(starts==before && !strcmp(folderLabel,"C:\\DOCUMENT\\MUSIC"));
    oldArray=tracksH; oldCount=trackCount; oldMemory=memoryCount;
    MSG_BSQP_LOAD_FOLDER(Request("bad","")); Pump();
    assert(tracksH==oldArray && trackCount==oldCount && memoryCount==oldMemory);
    failEnum=1; MSG_BSQP_LOAD_FOLDER(Request("\\music","")); Pump(); failEnum=0;
    assert(tracksH==oldArray && trackCount==oldCount && memoryCount==oldMemory);
    failVM=1; MSG_BSQP_LOAD_FOLDER(Request("\\music","")); Pump(); failVM=0;
    assert(tracksH==oldArray && memoryCount==oldMemory);
    MSG_BSQP_LOAD_FOLDER(Request("\\music","missing.mp3")); Pump();
    assert(tracksH==oldArray && starts==before && lastError==BQ_ERROR_OPEN);
    /* Cancel old queued batches; only the newest folder may commit. */
    MSG_BSQP_LOAD_FOLDER(Request("\\old",""));
    MSG_BSQP_LOAD_FOLDER(Request("\\new","")); Pump();
    assert(!strcmp(folderPath,"\\new"));
    /* Stop cancels a pending file launch before its scan finishes. */
    before=starts; MSG_BSQP_LOAD_FOLDER(Request("\\music","song060.WAV"));
    BQ_StopPlayback(); Pump(); assert(!scanRequestH && starts==before);
    /* Run through filename order exactly once. */
    selected=0; bqOptions=BQ_OPTION_CONTINUE; BQ_PlaySelected(); Pump();
    for(i=0;i<trackCount;++i) { assert(playingTrack==i); Complete(); }
    assert(!playFlag && !running);
    /* Shuffle visits each row once, including the explicitly chosen first. */
    memset(visited,0,sizeof(visited)); bqOptions=BQ_OPTION_CONTINUE|BQ_OPTION_SHUFFLE;
    selected=17; BQ_PlaySelected(); Pump(); assert(playingTrack==17);
    for(i=0;i<trackCount;++i) { assert(playingTrack<trackCount && !visited[playingTrack]); visited[playingTrack]=1; Complete(); }
    assert(!playFlag && !running);
    /* Repeat current takes priority; Stop cancels repeat and old completion. */
    bqOptions|=BQ_OPTION_ENDLESS; selected=9; BQ_PlaySelected(); Pump();
    Complete(); assert(playingTrack==9 && playFlag);
    BQ_StopPlayback(); Complete(); assert(!playFlag && !running && !strcmp(button,"PLAY"));
    /* A replacement waits for release. An obsolete result cannot advance. */
    bqOptions=BQ_OPTION_CONTINUE; selected=2; BQ_PlaySelected(); Pump(); serial=bqPlaySerial;
    selected=7; BQ_PlaySelected(); assert(pendingTrack==7 && playFlag);
    Complete(); assert(playingTrack==7 && playFlag && bqPlaySerial!=serial);
    assert(!BQ_FinishPlayback(123,serial) && playingTrack==7);
    /* Pending replacements collapse to the last selection. */
    selected=8; BQ_PlaySelected(); selected=12; BQ_PlaySelected(); Complete();
    assert(playingTrack==12 && playFlag);
    playFlag=BQ_PLAYFLAG_PAUSE; BQ_StopPlayback(); Complete();
    /* A stop timeout never permits a second worker. */
    selected=1; BQ_PlaySelected(); Pump(); before=starts;
    selected=3; BQ_PlaySelected(); ticks+=121; BQ_PollPending(); Pump();
    assert(starts==before && pendingTrack==BQ_NO_TRACK && lastError==BSNW_TIMEOUT);
    Complete(); assert(!playFlag);
    /* Failed opens/probes/threads stop the run and close only owned files. */
    before=errors; failOpen=1; BQ_PlaySelected(); Pump(); failOpen=0;
    assert(errors==before+1 && lastError==BQ_ERROR_OPEN && !fileOwned && !playFlag);
    probeResult=123; BQ_PlaySelected(); Pump(); probeResult=0;
    assert(lastError==123 && !fileOwned && !playFlag);
    failThread=1; BQ_PlaySelected(); Pump(); failThread=0;
    assert(lastError==BQ_ERROR_THREAD && !fileOwned && !playFlag);
    BQ_PlaySelected(); Pump(); playResult=123; Complete(); playResult=0;
    assert(lastError==123 && !running && !playFlag);
    /* New shuffle remainder excludes the current row. */
    bqOptions=0; BQ_PlaySelected(); Pump(); BQ_ResetShuffle();
    bqOptions=BQ_OPTION_CONTINUE|BQ_OPTION_SHUFFLE;
    next=BQ_NextTrack(); assert(next!=playingTrack && next<trackCount);
    BQ_StopPlayback(); Complete();
    /* The signed enumeration ceiling must not silently truncate a list. */
    MSG_BSQP_LOAD_FOLDER(Request("\\music",""));
    savedCount=scanCount; scanCount=BQ_MAX_TRACKS; Pump(); scanCount=savedCount;
    assert(lastError==BQ_ERROR_LIMIT && !scanRequestH);
    /* Launch copy owns its strings after the system block is released. */
    launchH=MemAlloc(sizeof(AppLaunchBlock),HF_DYNAMIC,HAF_ZERO_INIT);
    launchP=MemLock(launchH); launchP->ALB_diskHandle=2;
    strcpy(launchP->ALB_path,"\\music"); strcpy(launchP->ALB_dataFile,"song060.WAV");
    requestH=BQ_CopyLaunch(launchH); MemFree(launchH);
    MSG_BSQP_LOAD_FOLDER(requestH); Pump(); assert(playFlag); BQ_StopPlayback(); Complete();
    launchH=MemAlloc(sizeof(AppLaunchBlock),HF_DYNAMIC,HAF_ZERO_INIT);
    launchP=MemLock(launchH); memset(launchP->ALB_path,'x',sizeof(launchP->ALB_path));
    assert(BQ_CopyLaunch(launchH)==0xffff); MemFree(launchH);
    launchH=MemAlloc(sizeof(AppLaunchBlock),HF_DYNAMIC,HAF_ZERO_INIT);
    launchP=MemLock(launchH); strcpy(launchP->ALB_dataFile,"a.mp3");
    failAlloc=1; assert(BQ_CopyLaunch(launchH)==0xffff); failAlloc=0; MemFree(launchH);
    scanMatches=BQ_MAX_TRACKS;
    data.nameP="a.mp3"; assert(BQ_EnumAudio(&params,&data,0));
    assert(scanMatches==BQ_MAX_TRACKS+1UL);

    /* Empty and single-file folders terminate cleanly. */
    entryCount=0; before=starts; MSG_BSQP_LOAD_FOLDER(Request("\\empty","")); Pump();
    assert(!trackCount && starts==before && !fullPath[0]);
    entryCount=1; strcpy(entryNames[0],"only.mp3");
    MSG_BSQP_LOAD_FOLDER(Request("\\one","only.mp3")); Pump();
    bqOptions=BQ_OPTION_CONTINUE|BQ_OPTION_SHUFFLE; Complete(); assert(!playFlag);
    /* Directory/filename buffers must reject overflow. */
    memset(audioBytes,'x',sizeof(audioBytes)); audioBytes[250]=0;
    assert(!BQ_MakePath(fullPath,2,(char *)audioBytes,"long.mp3"));
    /* Shutdown cancels pending work while the old worker still owns its file. */
    selected=0; BQ_PlaySelected(); Pump();
    BQ_CloseFolder(); BQ_StopPlayback(); Complete(); Pump();
    assert(!playFlag && !vmOpen && deleted==1 && !memoryCount && !fileOwned && maxWorkers==1);
}
int main(int argc,char **argv)
{
    int i;
    assert(argc%2==1);
    for(i=1;i<argc;i+=2) CheckTag(argv[i],argv[i+1]);
    failAlloc=1; CheckTag(argv[1],"original.mp3"); failAlloc=0;
    shortRead=1; CheckTag(argv[1],"original.mp3"); shortRead=0;
    failSeek=1; CheckTag(argv[1],"original.mp3"); failSeek=0;
    CheckFolders();
    puts("Audio Quick Player ID3, folder scans, launch ownership, sequence/shuffle, stop/replacement/errors: PASS");
    return 0;
}
C
close $out or die $!;
sub syncsize { my $n=shift; return pack('C4', ($n>>21)&127, ($n>>14)&127, ($n>>7)&127, $n&127); }
sub frame {
    my ($v,$id,$data,$flags)=@_; $flags//=0;
    return $id.substr(pack('N',length($data)),1).$data if $v==2;
    return $id.($v==4 ? syncsize(length($data)) : pack('N',length($data))).pack('n',$flags).$data;
}
sub tag { my ($v,$body,$flags)=@_; return 'ID3'.pack('CCC',$v,0,$flags//0).syncsize(length($body)).$body; }
sub v1 { return 'TAG'.pack('a30a30a30a4a30C',$_[0],$_[1],'','', '',0); }
my @cases;
sub fixture { my ($name,$bytes,$expected)=@_; open my $f,'>',"$tmp/$name.bin" or die $!; binmode $f; print $f $bytes; close $f; push @cases,"$tmp/$name.bin",$expected; }
for my $v (2..4) {
    my ($ti,$ar)= $v==2 ? ('TT2','TP1') : ('TIT2','TPE1');
    fixture("v$v",tag($v,frame($v,$ti,"\0Title").frame($v,$ar,"\0Artist")), 'Artist - Title');
    fixture("v$v-title",tag($v,frame($v,$ti,"\0Title")), 'Title');
    fixture("v$v-fallback",tag($v,frame($v,$ar,"\0New artist")).v1('Old title','Old artist'), 'New artist - Old title');
    fixture("v$v-utf16le",tag($v,frame($v,$ti,"\1\xff\xfeT\0i\0t\0l\0e\0")), 'Title');
    fixture("v$v-utf16be",tag($v,frame($v,$ti,"\2\0T\0i\0t\0l\0e")), 'Title');
    fixture("v$v-utf8",tag($v,frame($v,$ti,"\3T\xc3\xbctle")), "T\x9ftle");
    fixture("v$v-malformed",tag($v,frame($v,$ti,"\3\xc0\xaf")).v1('Fallback','Artist'), 'Artist - Fallback');
    fixture("v$v-bounds",tag($v,frame($v,$ti,"\0x")), 'x');
    fixture("v$v-overlong",tag($v,frame($v,$ti,"\0".('x'x500))), 'x'x80);
    my $body=frame($v,$ti,"\0A\xffB").frame($v,$ar,"\0Artist");
    $body =~ s/\xff/\xff\0/g;
    fixture("v$v-unsync",tag($v,$body,128), "Artist - A\xd8B") if $v<4;
}
fixture('v1',('x'x20).v1('Title','Artist'),'Artist - Title');
fixture('no-title',tag(3,frame(3,'TPE1',"\0Artist")), 'original.mp3');
fixture('bad-header',"ID3\x05\0\0\0\0\0\0".v1('Fallback','Artist'),'Artist - Fallback');
fixture('bad-synchsafe',"ID3\x04\0\0\x80\0\0\0".v1('Fallback','Artist'),'Artist - Fallback');
fixture('truncated',substr(tag(3,frame(3,'TIT2',"\0Title")),0,-2),'original.mp3');
fixture('huge-frame',tag(3,'APIC'.pack('N',30000)."\0\0".('x'x30000).frame(3,'TIT2',"\0Title")), 'Title');
fixture('many-frames',tag(3,frame(3,'TXXX',"\0x")x257 .frame(3,'TIT2',"\0Title")), 'original.mp3');
fixture('v3-ext',tag(3,pack('N',6).("\0"x6).frame(3,'TIT2',"\0Title"),64),'Title');
fixture('v4-ext',tag(4,syncsize(6)."\1\0".frame(4,'TIT2',"\0Title"),64),'Title');
fixture('v4-unsync',tag(4,frame(4,'TIT2',"\0A\xff\0B",2).frame(4,'TPE1',"\0Artist")),"Artist - A\xd8B");
fixture('compressed',tag(3,frame(3,'TIT2',"\0Bad",128)).v1('Good','Artist'),'Artist - Good');
fixture('surrogate',tag(4,frame(4,'TIT2',"\1\xff\xfe\x3d\xd8\0\xde")), '?');
fixture('unpaired',tag(4,frame(4,'TIT2',"\1\xff\xfe\x3d\xd8")), 'original.mp3');
fixture('both-max',tag(4,frame(4,'TIT2',"\0".('T'x120)).frame(4,'TPE1',"\0".('A'x120))), ('A'x80).' - '.('T'x80));
fixture('budget',tag(3,frame(3,'APIC','x'x12000).frame(3,'TIT2',"\0Title"),128).v1('Fallback','Artist'),'Artist - Fallback');
fixture('v4-group-dli',tag(4,frame(4,'TIT2',"\7".syncsize(6)."\0Title",0x41)),'Title');
fixture('v4-bad-dli',tag(4,frame(4,'TIT2',"\x80\0\0\6\0Title",1)).v1('Fallback','Artist'),'Artist - Fallback');
fixture('bad-frame-size',tag(3,'TIT2'.pack('N',0xffffffff)."\0\0\0Title"),'original.mp3');
fixture('empty', '', 'original.mp3');
system('gcc','-std=c89','-pedantic-errors','-Werror=declaration-after-statement',
       '-funsigned-char','-g',"$tmp/check.c",'-o',"$tmp/check")==0 or die 'compile failed';
system("$tmp/check",@cases)==0 or die 'folder/tag check failed';
