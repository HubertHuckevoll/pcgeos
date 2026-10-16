/*
 * Private declarations shared by SourceCache.goc and ObjectCache.goc.
 *
 * CacheFileMapBlock describes the saved cache index and its name pool.
 * The URL-token and cache-policy helpers are near calls shared within
 * NAVCACHE_TEXT, so both implementations must use that code resource.
 * Include after htmlview.goh, which declares the public cache API.
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
