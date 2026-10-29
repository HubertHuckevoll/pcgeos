#!/usr/bin/env python3
"""Host-side regression checks for BSNWLoadCache (gcc/clang, no GEOS SDK).

Extracts the production function from Main/subcode.goc so the tests exercise
its real wraparound, short-read, EOF, and source-error bookkeeping. It cannot
test the GEOS callback calling convention, driver, interrupts, or DMA timing.
"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Main' / 'subcode.goc').read_text(encoding='latin-1')
start = source.index('int _pascal BSNWLoadCache(void *cachePtr)')
end = source.index('/*********************************************************', start)
function = source[start:end]

prefix = r'''
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
typedef uint16_t word;
typedef uint32_t dword;
typedef uint8_t byte;
typedef int Boolean;
#define _pascal
#define BSNW_STATUS_OK 0
#define BSNW_SOURCE_ERROR 8
#define BSNW_SOURCE_FILE 1
#define BSNW_SOURCE_CALL 2
#define BSNW_SOURCE_PCM 3
#define BSNW_PCM_READ_ERROR 0xffff
word cacheOffset, cacheFree, cacheFull, playCacheLen, playSourceType;
word pcmBlockAlign;
dword bytesToPlay, fullLen;
Boolean pcmUnknownLength;
static byte pcm[128], buffer[64];
static word pcmSize, pcmPos, maxChunk, readMode;
static void initSource(word mode, word n, dword total, Boolean unknown) {
    word i;
    memset(buffer, 0, sizeof(buffer));
    for (i=0; i<n; i++) pcm[i]=(byte)(i+1);
    pcmSize=n; pcmPos=0; maxChunk=0; readMode=mode;
    cacheOffset=0; cacheFree=32; cacheFull=0; playCacheLen=32;
    pcmBlockAlign=2; pcmUnknownLength=unknown;
    bytesToPlay=total; fullLen=unknown?0:total;
    playSourceType=BSNW_SOURCE_PCM;
}
word BSNWReadPCM(void *dest, word requested) {
    word result;
    if (readMode==1) return BSNW_PCM_READ_ERROR;
    if (readMode==2) return (word)(requested+1);
    if (pcmPos>=pcmSize) return 0;
    result=(word)(pcmSize-pcmPos);
    if (result>requested) result=requested;
    if (maxChunk && result>maxChunk) result=maxChunk;
    if (playSourceType != BSNW_SOURCE_PCM && result < requested)
        return BSNW_PCM_READ_ERROR;
    memcpy(dest,pcm+pcmPos,result);
    pcmPos+=result;
    return result;
}
'''

suffix = r'''
static void test_unknown_length_and_short_reads(void) {
    word i;
    initSource(0,14,0xffffffffUL,1);
    maxChunk=4;
    for (i=0; i<12 && bytesToPlay; i++)
        assert(BSNWLoadCache(buffer)==BSNW_STATUS_OK);
    assert(bytesToPlay==0);
    assert(fullLen==14);
    assert(cacheFull==14 && cacheFree==18);
    assert(pcmPos==14);
    assert(memcmp(buffer, pcm, 14)==0);
}
static void test_known_length_early_eof(void) {
    initSource(0,8,16,0);
    maxChunk=8;
    assert(BSNWLoadCache(buffer)==BSNW_STATUS_OK);
    assert(bytesToPlay==8 && fullLen==16);
    assert(BSNWLoadCache(buffer)==BSNW_STATUS_OK);
    assert(bytesToPlay==0 && fullLen==8);
    assert(cacheFull==8 && memcmp(buffer,pcm,8)==0);
}
static void test_error_and_invalid_counts(void) {
    initSource(1,8,0xffffffffUL,1);
    assert(BSNWLoadCache(buffer)==BSNW_SOURCE_ERROR);
    assert(bytesToPlay==0xffffffffUL && cacheFull==0);
    initSource(2,8,0xffffffffUL,1);
    assert(BSNWLoadCache(buffer)==BSNW_SOURCE_ERROR);
    initSource(0,8,0xffffffffUL,1);
    maxChunk=3;
    assert(BSNWLoadCache(buffer)==BSNW_SOURCE_ERROR);
}
static void test_wraparound_file(void) {
    initSource(0,10,10,0);
    playSourceType=BSNW_SOURCE_FILE;
    cacheOffset=28;
    assert(BSNWLoadCache(buffer)==BSNW_STATUS_OK);
    assert(cacheOffset==0 && bytesToPlay==6);
    assert(BSNWLoadCache(buffer)==BSNW_STATUS_OK);
    assert(cacheOffset==6 && bytesToPlay==0);
    assert(cacheFull==10 && cacheFree==22);
    assert(memcmp(buffer+28,pcm,4)==0);
    assert(memcmp(buffer,pcm+4,6)==0);
}
static void test_truncated_file_is_error(void) {
    initSource(0,2,8,0);
    playSourceType=BSNW_SOURCE_FILE;
    assert(BSNWLoadCache(buffer)==BSNW_SOURCE_ERROR);
    assert(cacheFull==0);
}
int main(void) {
    test_unknown_length_and_short_reads();
    test_known_length_early_eof();
    test_error_and_invalid_counts();
    test_wraparound_file();
    test_truncated_file_is_error();
    puts("PCM cache regression cases passed");
    return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
    cpath = Path(tmp) / 'pcm_cache_test.c'
    binary = Path(tmp) / 'pcm_cache_test'
    cpath.write_text(prefix + '\n' + function + '\n' + suffix)
    compiler = os.environ.get('CC','cc')
    subprocess.run([compiler,'-std=c99','-Wall','-Wextra','-Werror',str(cpath),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
