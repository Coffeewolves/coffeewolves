importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyCXs0XqqOS0WJwvZwMreagmG8UWZM1Anqg',
  appId: '1:639914979018:web:fbcf5b96118deefc308e33',
  messagingSenderId: '639914979018',
  projectId: 'wolves-club-fb24a',
  authDomain: 'wolves-club-fb24a.firebaseapp.com',
  storageBucket: 'wolves-club-fb24a.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  const orderId = data.orderId || 'order';
  if (data.action === 'acknowledged') {
    return self.registration
      .getNotifications({ tag: `cafe-order-${orderId}` })
      .then((notifications) => notifications.forEach((item) => item.close()));
  }
  const options = {
    body: data.body || 'Hay una nueva comanda para preparar.',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: data.productId
      ? `cafe-stock-${data.productId}`
      : `cafe-order-${orderId}`,
    renotify: true,
    requireInteraction: true,
    data: { url: data.url || '/', orderId, productId: data.productId || '' },
  };

  return self.registration.showNotification(
    data.title || 'Coffee Wolves · Nueva comanda',
    options,
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = new URL(
    event.notification.data?.url || '/',
    self.location.origin,
  ).href;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      (windowClients) => {
        for (const client of windowClients) {
          if (client.url.startsWith(self.location.origin) && 'focus' in client) {
            return client.focus();
          }
        }
        return clients.openWindow(targetUrl);
      },
    ),
  );
});
