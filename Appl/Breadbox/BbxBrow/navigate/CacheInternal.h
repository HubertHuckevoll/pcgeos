/* Private cache persistence layout and existing cross-source near helpers.
 * Both implementations must remain in NAVCACHE_TEXT for LOCAL calls.
 * Include after htmlview.goh; public cache declarations remain there.
 */
#ifndef BBXBROW_CACHE_INTERNAL_H
#define BBXBROW_CACHE_INTERNAL_H

/*
 * Map block of main cache file
 */
typedef struct {
    ReleaseNumber CFMB_release;   // Release number of geode creating file

    optr CFMB_cache;              // Cache index array

    VMChain CFMB_namePool;        // Name pool for cache array
} CacheFileMapBlock;


NameToken LOCAL CacheGetLocalToken(optr cachePool, NameToken url);
#ifdef ALT_SRC_CACHE
Boolean LOCAL UseAltCache(TCHAR *urlP);
#endif
#ifdef CACHE_VALIDATION
Boolean LOCAL SrcCacheIsExpired(dword expiration, Boolean *tryModified);
#endif

#endif
