self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", () => self.clients.claim());
self.addEventListener("fetch", (e) => {
  if (e.request.method === "POST") return;
  e.respondWith(fetch(e.request));
});
