#!/usr/bin/env perl
# Exercise the real selector, source lifecycle and timer code with host shims.
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Temp qw(tempdir);
my $app = abs_path(dirname(__FILE__).'/..');
my $tmp = tempdir('bsqp-XXXXXX', TMPDIR=>1, CLEANUP=>!$ENV{KEEP_TESTS});
sub read_file { open my $f, '<', $_[0] or die $!; local $/; return <$f>; }
my $audio = read_file("$app/Main/subcode.goc");
my $ui = read_file("$app/UI/uimain.goc");
my $process = read_file("$app/Main/process.goc");
for ($audio, $ui, $process) { s/\r\n/\n/g; }
die 'quick launch probes before reading saved options' unless
    index($process, 'InitFileReadInteger(cat,LMemDeref(@optionsKey)') <
    index($process, 'BQ_CheckForPlay();');
$audio =~ s{//([^\n]*)}{/*$1*/}g;
open my $out, '>', "$tmp/geos.h" or die $!;
print $out <<'HEADER';
#ifndef HOST_GEOS
#define HOST_GEOS
#include <stdint.h>
typedef uint8_t byte;
typedef uint16_t word;
typedef uint32_t dword;
typedef word MemHandle;
typedef dword optr;
typedef int Boolean;
#define _pascal
#define _export
#define TRUE 1
#define FALSE 0
#endif
HEADER
close $out or die $!;
open $out, '>', "$tmp/file.h" or die $!;
print $out "#include <geos.h>\ntypedef word FileHandle;\n#define FILE_POS_START 0\n";
print $out "dword FilePos(FileHandle, dword, word);\nword FileRead(FileHandle, void *, word, word);\n";
close $out or die $!;
open $out, '>', "$tmp/check.c" or die $!;
print $out <<'C';
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <bsnwav.h>
#define CODE_RIFF 0x46464952UL
#define FEA_FILE_ATTR 1
#define FEA_NAME 2
#define FA_SUBDIR 0x10
typedef byte FileAttrs;
typedef struct { FileAttrs attrs; const char *nameP; } FileEnumCallbackData;
static void *FileEnumLocateAttr(FileEnumCallbackData *dataP, word attr, void *unusedP)
{
    (void)unusedP;
    return attr == FEA_NAME ? (void *)dataP->nameP : (void *)&dataP->attrs;
}
static int LocalCmpStringsNoCase(const char *aP, const char *bP, word limit)
{
    (void)limit;
    while (*aP && tolower((unsigned char)*aP) == tolower((unsigned char)*bP)) {
        aP++; bP++;
    }
    return tolower((unsigned char)*aP) - tolower((unsigned char)*bP);
}
static dword bqSampleRate, bqAllBytes, bqSampleBytes;
static word bqChannels, bqBits;
static Boolean bqStopRequested;
static word bqOptions, expectedOptions;
static dword magic;
static int openResult, playResult, readerStatus, wavOpens, mp3Opens, wavCloses, mp3Closes, plays;
static Boolean fallback;
static word expectedFlags, readCount;
static Boolean failSeek;
static BSNPcmFormat format = { 44100, 2, 16, 4, 176400 };
dword FilePos(FileHandle fileH, dword offset, word mode)
{
    assert(fileH == 55 && !offset && mode == FILE_POS_START);
    return failSeek ? 0xffffffffUL : 0;
}
word FileRead(FileHandle fileH, void *destP, word count, word flags)
{
    assert(fileH == 55 && count == 4 && !flags);
    memcpy(destP, &magic, 4);
    return readCount;
}
int BSNWavOpen(BSNWav *wavP, FileHandle fileH)
{
    assert(fileH == 55); wavOpens++;
    wavP->source.format = format; wavP->source.pcmBytes = 176400;
    return openResult;
}
int BSNMP3DecOpenEx(BSNMP3Dec *mp3P, FileHandle fileH, word options)
{
    assert(fileH == 55 && options == (fallback && mp3Opens % 2 ? BSN_MP3_HALF_RATE : expectedOptions));
    mp3Opens++; mp3P->status = 0;
    mp3P->source.format = format; mp3P->source.pcmBytes = BSN_PCM_LENGTH_UNKNOWN;
    if (options) mp3P->source.format.sampleRate /= 2;
    return openResult;
}
void BSNWavClose(BSNWav *wavP) { (void)wavP; wavCloses++; }
void BSNMP3DecClose(BSNMP3Dec *mp3P) { (void)mp3P; mp3Closes++; }
int BSNPcmPlay(BSNPcmSource *sourceP, word flags, optr parent)
{
    assert(sourceP->format.sampleRate ==
           (magic != CODE_RIFF && (expectedOptions || fallback) ? format.sampleRate/2 : format.sampleRate));
    assert(flags == expectedFlags && !parent);
    if (magic != CODE_RIFF) ((BSNMP3Dec *)sourceP)->status = readerStatus;
    plays++; return playResult;
}
typedef word GStateHandle;
#define NullHandle 0
#define BQ_TIME_DISP_NORMAL 1
#define BQ_TIME_DISP_REMAIN 2
#define DISP_VIEW_X5 0
#define GrCreateState(a) 1
#define GrSetAreaColor(a,b,c,d,e) ((void)0)
#define GrFillRect(a,b,c,d,e) ((void)0)
#define GrSetFont(a,b,c) ((void)0)
#define GrSetTextColor(a,b,c,d,e) ((void)0)
#define GrTextWidth(a,b,c) 0
#define GrDrawText(a,b,c,d,e) strcpy(drawn,d)
#define GrDestroyState(a) ((void)0)
static word winHan = 1, bqDispStyle, playFlag;
static char globalText[80], drawn[80];
C
my $options = read_file("$app/Main/bsqp.goh");
while ($options =~ /^(#define BQ_\w+[^\r\n]*)/mg) { print $out "$1\n"; }
for my $name ('BQ_Audio', 'RedrawTime', 'BQ_FilterAudio') {
    my $source = $name eq 'BQ_FilterAudio' ? $ui : $audio;
    $source =~ /^((?:static )?[^\n;{}]*\b$name\s*\([^;]*?\)\n\{.*?^\})/ms
        or die "missing $name";
    print $out "$1\n";
}
print $out <<'C';
#define FILE_ACCESS_R 0
#define FILE_DENY_W 0
#define PRIORITY_HIGH 0
#define BQ_TIMEOUT_1 20
#define CDT_ERROR 3
#define GIT_NOTIFICATION 1
#define CDBF_DIALOG_TYPE_OFFSET 13
#define CDBF_INTERACTION_TYPE_OFFSET 9
static char fullPath[20], playText[] = "PLAY", pauseText[] = "PAUSE";
static const char *buttonText;
static word quickMode, rmsValue;
static Boolean capabFlag = TRUE, bqMinimizedState;
static int failOpen, failThread, fileOwned, fileCloses, threadCreates;
static int pending, pendingResult, dialogs, quits, sequence, dialogSequence;
static Boolean pendingClose;
static optr shownText;
word BQ_PlayThread(word fileH);
static FileHandle FileOpen(const char *pathP, word flags)
{
    (void)pathP; (void)flags; assert(!fileOwned);
    fileOwned = !failOpen; return fileOwned ? 55 : 0;
}
static void FileClose(FileHandle fileH, Boolean noError)
{
    assert(fileH == 55 && noError && fileOwned);
    fileOwned = 0; fileCloses++;
}
static int ThreadCreate(word priority, word fileH, word (*entryP)(word),
                        word stack, word owner)
{
    (void)priority; (void)owner;
    assert(fileH == 55 && entryP == BQ_PlayThread && stack == 3000 && fileOwned);
    threadCreates++; return !failThread;
}
#define GeodeGetProcessHandle() 1
static void TimerSleep(word ticks) { (void)ticks; }
static void BSNWaveStop(void) { }
static void BSNWaveSetPause(word mode) { (void)mode; }
static void RedrawStatus(word state) { (void)state; }
static void RedrawRMS(word state) { (void)state; }
static void RedrawFileName(word state) { (void)state; }
static void RedrawSettings(word state) { (void)state; }
static void QueueFinished(int result, Boolean closeAfter)
{
    assert(!pending && (!playFlag || result == BSNW_TIMEOUT));
    if (!playFlag) assert(!fileOwned);
    pending = 1; pendingResult = result; pendingClose = closeAfter;
}
static void Quit(void) { quits++; sequence++; }
static void UserStandardDialogOptr(char *helpP, void *triggersP,
                                   optr arg2, optr arg1, optr text, word flags)
{
    assert(!helpP && !triggersP && !arg2 && !arg1);
    assert(flags == ((CDT_ERROR << CDBF_DIALOG_TYPE_OFFSET) |
                     (GIT_NOTIFICATION << CDBF_INTERACTION_TYPE_OFFSET)));
    shownText = text; dialogs++; dialogSequence = ++sequence;
}
C
my @texts = $process =~ /\@chunk char (BQ\w+)\[\]/g;
print $out "enum { BQNoText, ", join(', ', @texts), " };\n";
$process =~ /^\@method BSQPProcessClass, MSG_PROCESS_BSQP_FINISHED\n(\{.*?^\})/ms
    or die 'missing completion method';
my $finished = "static void Finished(int result, Boolean closeAfter)\n$1";
$finished =~ s/\@(BQ\w+)/$1/g;
$finished =~ s/\@send PLAYTrigger::MSG_GEN_REPLACE_VIS_MONIKER_TEXT\((\w+), VUM_NOW\);/buttonText = $1;/g;
$finished =~ s/\@send BSQPPrimary::MSG_GEN_DISPLAY_SET_MINIMIZED\(\);/(void)0;/g;
$finished =~ s/\@send BSQPApp::MSG_META_QUIT\(\);/Quit();/g;
die 'unhandled completion GOC' if $finished =~ /\@/;
print $out "$finished\n";
for my $name (qw(BQ_StartPlay BQ_PlayThread BQ_CheckForPlay)) {
    $audio =~ /^([^\n;{}]*\b$name\s*\([^;]*?\)\n\{.*?^\})/ms or die "missing $name";
    my $definition = $1;
    $definition =~ s/\@send process::MSG_PROCESS_BSQP_FINISHED\(/QueueFinished(/g;
    $definition =~ s/\@send PLAYTrigger::MSG_GEN_REPLACE_VIS_MONIKER_TEXT\((\w+),\s*VUM_NOW\);/buttonText = $1;/g;
    $definition =~ s/\@send PLAYTrigger::MSG_GEN_SET_ENABLED\(VUM_NOW\);/(void)0;/g;
    die "unhandled $name GOC" if $definition =~ /\@/;
    print $out "$definition\n";
}
print $out <<'C';
static void Deliver(void)
{
    assert(pending); pending = 0;
    Finished(pendingResult, pendingClose);
}
static void CheckLifecycle(void)
{
    static const int errors[] = {BQ_ERROR_OPEN, BQ_ERROR_THREAD, BSNW_WRONG_DRIVER,
        BSNW_MEMORY_ERROR, BSNW_NOT_FREE, BSNW_HARDWARE_NOT_READY, BSNW_READ_ERROR,
        BSNW_TRUNCATED, BSNW_INVALID_DATA, BSNW_FORMAT_CHANGED,
        BSNW_UNKNOWN_WAVE_FORMAT, BSNW_TIMEOUT, BSNW_SOURCE_ERROR};
    optr previous[sizeof(errors)/sizeof(errors[0])];
    unsigned i, j;
    int oldDialogs, oldCloses;
    playFlag = 0;
    for (i=0; i<sizeof(errors)/sizeof(errors[0]); i++) {
        Finished(errors[i], FALSE); previous[i] = shownText;
        for (j=0; j<i; j++) assert(previous[j] != previous[i]);
    }
    oldDialogs = dialogs;
    Finished(BSNW_STATUS_OK, FALSE); Finished(BSNW_ABORT, FALSE);
    assert(dialogs == oldDialogs);
    readCount = 4; magic = 0x00334449UL; format.sampleRate = 44100;
    /* Selection changes only update metadata; they must stay silent. */
    openResult = BSNW_INVALID_DATA;
    assert(!BQ_CheckForPlay() && !pending && dialogs == oldDialogs && !fileOwned);
    /* Explicit play closes failed probes before it queues an error. */
    oldCloses = fileCloses;
    BQ_StartPlay(); assert(pendingResult == BSNW_INVALID_DATA && !playFlag);
    assert(fileCloses == oldCloses+1 && dialogs == oldDialogs);
    Deliver(); assert(dialogs == oldDialogs+1 && !quits);
    openResult = 0; failOpen = 1; quickMode = BQ_QUICK_START;
    BQ_StartPlay(); assert(pendingResult == BQ_ERROR_OPEN && pendingClose && !quits);
    Deliver(); assert(shownText == BQOpenError && quits == 1 && sequence == dialogSequence+1);
    failOpen = 0; failThread = 1; quickMode = 0; expectedFlags = BSNW_TEST_ONLY;
    BQ_StartPlay(); assert(pendingResult == BQ_ERROR_THREAD && !fileOwned && !playFlag);
    Deliver(); assert(buttonText == playText && shownText == BQThreadError);
    failThread = 0; playResult = 0;
    BQ_StartPlay(); assert(fileOwned && playFlag && !pending);
    playResult = BSNW_SOURCE_ERROR; readerStatus = BSNW_TRUNCATED; expectedFlags = 0;
    assert(!BQ_PlayThread(55) && !fileOwned && !playFlag);
    assert(pendingResult == BSNW_TRUNCATED); Deliver();
    /* Cancellation does not show an error; quick exit follows completion. */
    playResult = readerStatus = 0; quickMode = BQ_QUICK_START;
    expectedFlags = BSNW_TEST_ONLY; BQ_StartPlay();
    bqStopRequested = TRUE; oldDialogs = dialogs;
    assert(!BQ_PlayThread(55) && pendingResult == BSNW_ABORT);
    Deliver(); assert(dialogs == oldDialogs && quits == 2);
    /* A stop timeout reports the error without releasing the live worker. */
    quickMode = 0; playFlag = BQ_PLAYFLAG_PLAY;
    BQ_StartPlay(); assert(pendingResult == BSNW_TIMEOUT && playFlag && !pendingClose);
    Deliver(); playFlag = 0; bqStopRequested = FALSE;
}
C
print $out <<'C';
int main(void)
{
    static const char *accepted[] = {"a.WAV", "a.mp3", "many.dots.Mp3", ".wav"};
    static const char *rejected[] = {"a.mp3.exe", "wav", "a.wavx", "a.", "a.txt", ""};
    FileEnumCallbackData data;
    unsigned i, mp3, preview;
    data.attrs = 0;
    for (i=0; i<sizeof(accepted)/sizeof(accepted[0]); i++) {
        data.nameP = accepted[i]; assert(!BQ_FilterAudio(0, &data, 0));
    }
    for (i=0; i<sizeof(rejected)/sizeof(rejected[0]); i++) {
        data.nameP = rejected[i]; assert(BQ_FilterAudio(0, &data, 0));
    }
    data.nameP = (void *)0; assert(BQ_FilterAudio(0, &data, 0));
    data.attrs = FA_SUBDIR; assert(!BQ_FilterAudio(0, &data, 0));
    data.nameP = "music"; assert(!BQ_FilterAudio(0, &data, 0));
    readCount = 4;
    for (mp3=0; mp3<2; mp3++) {
        magic = mp3 ? 0x00334449UL : CODE_RIFF;
        for (preview=0; preview<2; preview++) {
            expectedFlags = preview ? BSNW_TEST_ONLY : 0;
            assert(BQ_Audio(55, preview) == BSNW_STATUS_OK);
            assert(bqAllBytes == (mp3 ? BSN_PCM_LENGTH_UNKNOWN : 176400));
            assert(bqSampleRate == 44100 && bqChannels == 2 && bqBits == 16);
            assert(bqSampleBytes == 0);
        }
        openResult = BSNW_SOURCE_ERROR; i = plays;
        assert(BQ_Audio(55, FALSE) == BSNW_SOURCE_ERROR && plays == (int)i);
        openResult = 0; playResult = BSNW_UNKNOWN_WAVE_FORMAT;
        expectedFlags = BSNW_TEST_ONLY;
        assert(BQ_Audio(55, TRUE) == BSNW_UNKNOWN_WAVE_FORMAT);
        playResult = 0; bqStopRequested = TRUE; i = plays;
        assert(BQ_Audio(55, FALSE) == BSNW_ABORT && plays == (int)i);
        assert(BQ_Audio(55, TRUE) == BSNW_STATUS_OK);
        bqStopRequested = FALSE;
    }
    assert(wavOpens == wavCloses && mp3Opens == mp3Closes);
    /* The saved option affects MP3 probe and playback, but not WAV. */
    bqOptions = BQ_OPTION_MP3_HALF_RATE; expectedOptions = BSN_MP3_HALF_RATE;
    for (mp3=0; mp3<2; mp3++) {
        magic = mp3 ? 0x00334449UL : CODE_RIFF;
        for (preview=0; preview<2; preview++) {
            expectedFlags = preview ? BSNW_TEST_ONLY : 0;
            assert(BQ_Audio(55, preview) == BSNW_STATUS_OK);
            assert(bqSampleRate == (mp3 ? 22050 : 44100));
        }
    }
    bqOptions = expectedOptions = 0;
    /* A valid 48 kHz MP3 uses filtered 24 kHz output even at default quality. */
    magic = 0x00334449UL; format.sampleRate = 48000;
    mp3Opens = mp3Closes = 0; fallback = TRUE;
    for (preview=0; preview<2; preview++) {
        expectedFlags = preview ? BSNW_TEST_ONLY : 0;
        assert(BQ_Audio(55, preview) == BSNW_STATUS_OK);
        assert(bqSampleRate == 24000 && !bqOptions);
    }
    assert(mp3Opens == 4 && mp3Closes == 4);
    fallback = FALSE; format.sampleRate = 44100;
    /* Preserve a decoder diagnosis when the PCM layer returns SOURCE_ERROR. */
    expectedFlags = 0; playResult = BSNW_SOURCE_ERROR;
    for (readerStatus=BSNW_READ_ERROR; readerStatus<=BSNW_FORMAT_CHANGED; readerStatus++)
        assert(BQ_Audio(55, FALSE) == readerStatus);
    playResult = readerStatus = 0;
    i = plays; failSeek = TRUE;
    assert(BQ_Audio(55, FALSE) == BSNW_READ_ERROR && plays == (int)i);
    failSeek = FALSE; readCount = 3;
    assert(BQ_Audio(55, FALSE) == BSNW_INVALID_DATA && plays == (int)i);
    readCount = 0xffff;
    assert(BQ_Audio(55, FALSE) == BSNW_READ_ERROR && plays == (int)i);
    bqChannels = 1; bqSampleRate = 8000; bqBits = 16;
    bqAllBytes = BSN_PCM_LENGTH_UNKNOWN; bqSampleBytes = 16000*70000UL;
    bqDispStyle = BQ_TIME_DISP_REMAIN; playFlag = 1;
    RedrawTime(1); assert(!strcmp(drawn, "19:26:40"));
    bqAllBytes = 16000*100UL; bqSampleBytes = 16000*101UL;
    RedrawTime(1); assert(!strcmp(drawn, "-0:00:00"));
    bqSampleBytes = 16000*99UL;
    RedrawTime(1); assert(!strcmp(drawn, "-0:00:01"));
    bqDispStyle = BQ_TIME_DISP_NORMAL; bqAllBytes = BSN_PCM_LENGTH_UNKNOWN;
    bqSampleBytes = 16000*3600UL;
    RedrawTime(1); assert(!strcmp(drawn, "1:00:00"));
    CheckLifecycle();
    puts("Audio Quick Player filter, 48 kHz fallback, error dialogs, cleanup, cancel/probe and time: PASS");
    return 0;
}
C
close $out or die $!;
system('gcc', '-std=c89', '-pedantic-errors', '-Werror=declaration-after-statement',
       '-I', $tmp, '-I', "$app/../../../CInclude", "$tmp/check.c", '-o', "$tmp/check") == 0
    or die 'compile failed';
system("$tmp/check") == 0 or die 'Audio Quick Player checks failed';
