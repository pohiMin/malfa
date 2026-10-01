/* ============================================================
   热血玛法 1.76 —— Service Worker  v2
   ------------------------------------------------------------
   缓存策略（分两类，这是"改完上传就自动同步"的关键）：

   1) 页面本体（index.html / 根路径）→ 【网络优先】
      联网时永远拉最新版，断网才回退缓存。
      否则玩家会一直看到旧版本（缓存优先的经典坑）。

   2) 静态资源（图标、manifest）→ 【缓存优先】
      这些很少变，走缓存更快。

   更新流程：
      浏览器每次打开都会拉这个 sw.js，字节有变化 → 装新 SW
      → 页面端监听 onupdatefound / newWorker 状态 → 弹提示条
      → 用户点击 → postMessage({type:'SKIP_WAITING'}) → 新 SW 接管
      → 页面 reload → 拿到最新游戏。

   注意：CACHE_VERSION 由 deploy.py 自动写入时间戳，无需手动改。
   ============================================================ */
const CACHE_VERSION = 'malfa-20261001-184846';
const PAGE_ASSETS = ['./', './index.html'];
const STATIC_ASSETS = [
  './manifest.json',
  './icons/icon-48.png',
  './icons/icon-72.png',
  './icons/icon-96.png',
  './icons/icon-144.png',
  './icons/icon-152.png',
  './icons/icon-180.png',
  './icons/icon-192.png',
  './icons/icon-512.png'
];

/* 安装：预缓存静态资源；页面本体也缓存一份作为离线兜底 */
self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_VERSION).then((cache) =>
      // 单个资源失败不影响整体安装
      Promise.all(
        PAGE_ASSETS.concat(STATIC_ASSETS).map((u) =>
          cache.add(u).catch(() => null)
        )
      )
    ).then(() => {
      // 注意：这里不自动 skipWaiting —— 交给页面提示用户后手动触发，
      // 避免玩家正打 BOSS 时被强制刷新打断。
    })
  );
});

/* 页面发来 SKIP_WAITING → 立即接管 */
self.addEventListener('message', (e) => {
  if (e.data && e.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

/* 激活：清掉所有旧版本缓存 */
self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

/* 判断是否属于"页面本体"请求 */
function isPageRequest(url) {
  const p = url.pathname;
  return p.endsWith('/') || p.endsWith('/index.html') || p.endsWith('.html');
}

/* 请求拦截 */
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.origin !== location.origin) return;

  // ---------- 页面本体：网络优先，失败回退缓存 ----------
  if (isPageRequest(url)) {
    e.respondWith(
      fetch(e.request)
        .then((resp) => {
          if (resp && resp.status === 200) {
            const copy = resp.clone();
            caches.open(CACHE_VERSION).then((c) => c.put(e.request, copy));
          }
          return resp;
        })
        .catch(() =>
          caches.match(e.request, { ignoreSearch: true })
            .then((cached) => cached || caches.match('./index.html'))
        )
    );
    return;
  }

  // ---------- 静态资源：缓存优先，网络兜底 ----------
  e.respondWith(
    caches.match(e.request, { ignoreSearch: true }).then((cached) => {
      if (cached) return cached;
      return fetch(e.request).then((resp) => {
        if (resp && resp.status === 200) {
          const copy = resp.clone();
          caches.open(CACHE_VERSION).then((c) => c.put(e.request, copy));
        }
        return resp;
      }).catch(() => caches.match('./index.html'));
    })
  );
});
