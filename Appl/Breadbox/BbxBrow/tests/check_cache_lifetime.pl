#!/usr/bin/env perl
# Exercise the actual shared-cache routines with host resource/event stubs.
# This checks ownership and ordering, not GEOS message scheduling or VM I/O.
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);

sub read_source {
    open my $file, '<:raw', "$FindBin::Bin/../$_[0]" or die $!;
    local $/;
    return <$file>;
}
my $code = read_source('cache/CacheLifetime.goc');
$code =~ s/\A.*?(?=\/\* Name management \*\/)//s or die "Missing lifetime state\n";
$code =~ /static word cacheFileRefCount;/ or die "Counter is not private\n";
my $text = read_source('urltext/URLText.goc');
$text =~ /MSG_HTML_TEXT_INIT_STORAGE\s*\{\s*AddCacheFileReference\(\);[^\n]*\n\s*\@callsuper\(\);/s
    or die "Text storage must acquire before initialization\n";
$text =~ /MSG_HTML_TEXT_DEINIT_STORAGE\s*\{\s*\@callsuper\(\);\s*RemoveCacheFileReference\(\);/s
    or die "Text storage must detach before releasing\n";
my $doc = read_source('urldoc/URLDOC.goc');
$doc =~ /\@method URLDocumentClass, MSG_GEN_DOCUMENT_PHYSICAL_CLOSE\s*\{(.*?)^}/ms
    or die "Missing document close\n";
index($1, 'MSG_URL_FRAME_DESTRUCT_TEXT_TREE') < index($1, 'RemoveCacheFileReference();')
    && index($1, 'MSG_URL_FRAME_DESTRUCT_TEXT_TREE') >= 0
    or die "Document must retain its reference through text destruction\n";

my $tmp = tempdir(CLEANUP => 1);
open my $test, '>', "$tmp/check.c" or die $!;
print $test <<'C';
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define _pascal
#define _TEXT(s) s
#define NullWatcher 0
#define NullOptr 0
#define NullHandle 0
#define HTMLVIEW_CATEGORY "HTMLView"
#define HTML_CACHE_SP 1
#define HTML_CACHE_DIR "SOURCE"
#define HTML_VMCACHE_SP 2
#define HTML_VMCACHE_DIR "CACHE"
#define TEXT_OBJ_FILE_NAME "TEXT.VM"
#define NUM_CACHE_FILES 2
#define VMAF_FORCE_READ_WRITE 1
#define VMO_CREATE_TRUNCATE 2
#define VMA_OBJECT_ATTRS 7
#define VMA_OBJECT_RELOC 1
#define FILE_NO_ERRORS 0
#define xstrncpy strncpy

typedef unsigned short word;
typedef unsigned long dword;
typedef int optr;
typedef int AllocWatcherHandle;
typedef char TCHAR;
static int cacheFiles[NUM_CACHE_FILES] = {10, 11}, srcCacheFile = 12;
static int textObjFile;
static int objCacheBlock = 20, objCacheArray, srcCacheArray;
static int srcCacheSem = 40, objCacheSem = 41;
static int altSrcCacheHosts, altSrcCacheExts;
static void *jsecontext;
extern optr namePool;
extern AllocWatcherHandle G_allocWatcher;
static char events[512];
static int live[64], clients, configured;
void AddCacheFileReference(void);
void RemoveCacheFileReference(void);

static void record(const char *eventP)
{
    assert(strlen(events) + strlen(eventP) < sizeof(events));
    strcat(events, eventP);
}
static int acquire(int handle)
{
    assert(!live[handle]); live[handle] = 1; return handle;
}
static void release(int handle)
{
    assert(live[handle]); live[handle] = 0;
}
#define HWChecksumCheck() record("check ")
static int InitFileReadInteger(const char *categoryP, const char *keyP, word *valueP)
{
    assert(strcmp(categoryP, HTMLVIEW_CATEGORY) == 0);
    if (!configured) return 1;
    if (strcmp(keyP, "memlimit") == 0) *valueP = 123;
    else { assert(strcmp(keyP, "vmCacheSP") == 0); *valueP = 3; }
    return 0;
}
static int InitFileReadStringBuffer(const char *categoryP, const char *keyP,
                                  char *bufP, word size, word *lengthP)
{
    assert(strcmp(categoryP, HTMLVIEW_CATEGORY) == 0);
    assert(strcmp(keyP, "vmCacheDir") == 0 && size >= 7);
    if (!configured) return 1;
    strcpy(bufP, "CUSTOM"); *lengthP = 7; return 0;
}
static int AllocWatcherCreate(dword limit)
{
    assert(limit == (configured ? 123000UL : 0x400000UL));
    record("watcher "); return acquire(30);
}
static void FileSetCurrentPath(word sp, const char *pathP)
{
    assert((sp == 1 && strcmp(pathP, ".") == 0) ||
           (sp == 2 && strcmp(pathP, "CACHE") == 0) ||
           (configured && sp == 3 && strcmp(pathP, "CUSTOM") == 0));
    record("path ");
}
static void FileCreateDir(const char *pathP)
{
    assert(strcmp(pathP, "SOURCE") == 0); record("mkdir ");
}
static void AttachToObjCache(void)
{
    assert(live[G_allocWatcher]); record("objects ");
    acquire(10); acquire(11); acquire(20); acquire(41); objCacheArray = 21;
}
static int VMOpen(const char *nameP, int access, int mode, int compression)
{
    assert(strcmp(nameP, "TEXT.VM") == 0);
    assert(access == 1 && mode == 2 && compression == 1);
    record("open "); return acquire(13);
}
static void VMSetAttributes(int file, int attrs, int clear)
{
    assert(file == 13 && live[file] && attrs == 6 && clear == 0);
    record("attributes ");
}
static int NamePoolCreate(int file)
{
    assert(file == 13 && live[file]);
    record("pool "); return acquire(31);
}
static void AttachToSrcCache(void)
{
    assert(live[namePool]); record("sources ");
    acquire(12); acquire(40); srcCacheArray = 22;
}
static void ExitBrowserJS(void)
{
    assert(jsecontext && live[namePool]); record("js "); jsecontext = NULL;
}
static void DetachFromObjCache(void)
{
    assert(!clients && live[namePool] && live[10] && live[41]);
    record("persist-objects ");
}
static void SrcCacheCommit(void)
{
    assert(live[namePool] && live[12] && live[40]); record("persist-source ");
}
static void MemFree(int handle)
{
    if (handle == 20) record("block ");
    else {
        assert(!srcCacheArray && !objCacheArray);
        assert(handle == 50 || handle == 51);
        record(handle == 50 ? "hosts " : "exts ");
    }
    release(handle);
}
static void NamePoolFree(int pool)
{
    assert(!srcCacheArray && !objCacheArray && pool == 31);
    record("free-pool "); release(pool);
}
static void VMClose(int file, int flags)
{
    assert(!clients && !namePool && flags == 0 && live[40] && live[41]);
    record("close "); release(file);
}
static void AllocWatcherDestroy(int watcher)
{
    assert(watcher == 30 && !live[10] && !live[11] && !live[12] && !live[13]);
    record("free-watcher "); release(watcher);
}
static void ThreadFreeSem(int sem)
{
    assert(!G_allocWatcher); record("free-sem "); release(sem);
}
C
print $test $code;
print $test <<'C';
int main(void)
{
    /* navigation, document, text A, text B; system detach closes navigation first. */
    static const int order[2][4] = {{3, 2, 1, 0}, {0, 3, 2, 1}};
    int detach, mask, i;
    char expected[512];
    for (configured = 0; configured < 2; configured++) {
        for (detach = 0; detach < 2; detach++) {
            for (mask = 0; mask < (ALT_BUILD ? 4 : 1); mask++) {
                assert(!namePool && !G_allocWatcher);
                events[0] = 0; clients = 1;
                vmCacheSP = HTML_VMCACHE_SP;
                jsecontext = (void *)1;
                InitCacheLifetime();
                strcpy(expected, "check watcher check path mkdir check path objects "
                                 "open attributes pool path sources check ");
                assert(strcmp(events, expected) == 0);
                if (JS_BUILD) assert(!jsecontext);
                events[0] = 0;
                for (i = 1; i < 4; i++) {
                    clients |= 1 << i; AddCacheFileReference();
                }
                assert(!events[0]);
                altSrcCacheHosts = mask & 1 ? acquire(50) : 0;
                altSrcCacheExts = mask & 2 ? acquire(51) : 0;
                jsecontext = configured ? (void *)1 : NULL;
                for (i = 0; i < 4; i++) {
                    clients &= ~(1 << order[detach][i]); RemoveCacheFileReference();
                    if (i < 3) assert(!events[0] && namePool && G_allocWatcher);
                }
                strcpy(expected, JS_BUILD && configured ? "js " : "");
                strcat(expected, "persist-objects persist-source block ");
                if (mask & 1) strcat(expected, "hosts ");
                if (mask & 2) strcat(expected, "exts ");
                strcat(expected, "free-pool close close close close path ");
                strcat(expected, "free-watcher free-sem free-sem ");
                assert(strcmp(events, expected) == 0);
                assert(!namePool && !G_allocWatcher && !srcCacheArray && !objCacheArray);
                assert(!altSrcCacheHosts && !altSrcCacheExts);
                for (i = 0; i < 64; i++) assert(!live[i]);
            }
        }
    }
    return 0;
}
C
close $test or die $!;
for my $alt (0, 1) {
    for my $js (0, 1) {
        my @flags = ("-DALT_BUILD=$alt", "-DJS_BUILD=$js",
                     "-DJAVASCRIPT_SUPPORT=$js");
        push @flags, '-DALT_SRC_CACHE' if $alt;
        system('cc', '-std=gnu89', '-Wall', '-Wextra', '-Werror',
               '-Wno-unused-function', @flags, "$tmp/check.c", '-o', "$tmp/check") == 0
            or die "Host compilation failed\n";
        system("$tmp/check") == 0 or die "Cache lifetime check failed\n";
    }
}
print "Cache lifetime: all 4 feature combinations passed\n";
