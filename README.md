# Coffee Wolves

Prototipo Flutter para la comunidad Coffee Wolves: cafetería de especialidad,
menú, pedidos y experiencia pet friendly.

## Ejecutar

```powershell
flutter pub get
flutter run -d chrome
```

### Firebase Cloud

La aplicación inicializa Firebase con `DefaultFirebaseOptions.currentPlatform`
en `lib/main.dart`; las opciones web de `lib/firebase_options.dart` apuntan al
proyecto `wolves-club-fb24a`. El registro y el inicio de sesión por correo
utilizan Firebase Authentication en la nube. En Firebase Console, verifica que
esté habilitado el proveedor **Correo electrónico/contraseña** en
Authentication > Proveedores de acceso y que el dominio publicado figure en
Authentication > Configuración > Dominios autorizados.

El plan Spark permite Firebase Authentication y Firestore. Las fotos del Muro
se guardan como JPEG optimizados en Firestore (máximo 200 KB) y los videos
como clips MP4, MOV o WebM de hasta 15 segundos y 5 MB. Los videos se dividen
en documentos Firestore para respetar el límite de tamaño por documento. Estas
publicaciones no requieren Storage ni crean un bucket. Las galerías de mascotas
y otras funciones que sí usan Firebase Storage seguirán necesitando ese
servicio. La app no activa Blaze.

#### Retención de publicaciones del Muro

Todas las publicaciones vencen exactamente 7 días después de su creación,
independientemente del tamaño de la comunidad o del volumen diario. Firestore
Rules limita la fecha de expiración y el feed oculta las publicaciones vencidas.
Un workflow de GitHub Actions limpia las publicaciones y los fragmentos de
video cada hora; por la periodicidad del proceso, el borrado puede ocurrir
hasta una hora después del vencimiento. El script también migra las fechas de
publicaciones antiguas a creación + 7 días y las borra si ya vencieron.

Para habilitar las tareas automáticas, configura el secreto de repositorio
`FIREBASE_SERVICE_ACCOUNT_WOLVES_CLUB_FB24A` con una clave JSON de una cuenta de
servicio del proyecto `wolves-club-fb24a`. La cuenta debe poder leer/escribir
Firestore; para el despliegue de reglas e índices también necesita permisos de
administración de Firebase Rules e índices de Firestore. Los workflows
`cleanup-mischief-posts.yml` y `deploy-firestore.yml` se ejecutan en GitHub
Actions tras el push; el primero migra las publicaciones existentes y luego
se repite cada hora. La aplicación web se publica por separado mediante
`deploy-pages.yml`.

La pantalla deja de mostrar publicaciones vencidas y actualiza el listado cada
minuto. Para ejecutar una limpieza manual durante el desarrollo:

```bash
cd functions
npm install
node cleanup_mischief_posts.js --migrate
```

Esta estrategia consume cuota de Firestore Spark; las imágenes se convierten a
Base64 y los videos generan múltiples escrituras y lecturas. El proceso local
o GitHub Actions no activa Blaze ni crea un bucket.

## Menú

El catálogo se basa en las cartas publicadas en [Google Sites](https://sites.google.com/view/coffeewolves/menu)
y en su [menú pet friendly](https://sites.google.com/view/coffeewolves/pet-friendly/menu).
Incluye búsqueda, filtros por categoría, detalle de producto, carrito y pedidos
por WhatsApp.

La identidad visual usa los tonos espresso, marfil y dorado de Coffee Wolves.
La interfaz usa Montserrat Light para una lectura ligera y uniforme.
La pantalla inicial obliga a crear una cuenta o iniciar sesión; la pantalla
principal solo aparece cuando Firebase confirma un número de teléfono asociado.
En Web, el botón de nota musical en la pantalla principal activa o silencia la
canción oficial en bucle y a volumen bajo. El audio usa el elemento HTML `Audio`
mediante importación condicional, por lo que las compilaciones nativas no
importan `dart:html`; la música de fondo se limita a Web. El timbre de pedidos
reproduce un WAV en el navegador y usa el sonido de alerta del sistema en
compilaciones nativas.
En la pantalla inicial y en Home hay botones visibles «GERENCIA» y
«BARRA / CAJA» para abrir el acceso del equipo sin gestos ocultos. El formulario
propone `Admin@coffeewolves.com` o `barra@coffeewolves.com` como correo editable;
cada persona define su contraseña al solicitar su cuenta. Los formularios
siguen exigiendo autenticación y rol. Baristas y
cajeros inician sesión con correo y contraseña de Firebase verificados; la app
lee `users/{uid}.role` desde Firestore. Baristas y cajeros entran directamente
al TPV y quedan limitados a esa operación. Gerencia entra al panel administrativo
y puede abrir el TPV únicamente con el botón «ABRIR TPV» del panel; la cuenta
de Gerencia no puede entrar por el acceso «TPV · Personal». Al salir del TPV
vuelve al panel. En Flutter Web,
Firebase Auth usa persistencia local:
la sesión se restaura al volver a abrir el navegador mientras no se cierre
sesión, se borren los datos del navegador o se revoque la cuenta. Al recuperar
una cuenta `cajero`, la app vuelve directamente al TPV. El inicio de turno y la
apertura de caja siguen siendo obligatorios para registrar ventas. Las reglas
de Firestore también validan los roles.
Gerencia puede iniciar sesión desde cualquier Wi-Fi o conexión de datos con
acceso a Internet; no se comprueba SSID ni ubicación. Requiere
correo/contraseña, correo verificado y `users/{uid}.role == "admin"` o
`role`/`rol == "gerente"`; ambas variantes se autorizan como Gerencia. El panel
ofrece indicadores de la sesión y lectura de los últimos 50 documentos
de `wolvesShopOrders`. No representa ventas de cafetería ni estados de caja:
esos datos todavía no se guardan en una colección persistente. La sesión de
gerencia se bloquea tras dos minutos sin actividad. La administración del
catálogo actual solo vive en memoria y no persiste en Firestore.
Los roles se leen de `users/{uid}.role` (con compatibilidad para el campo `rol`)
y valores válidos son `cliente`, `barista`, `cajero`, `admin` y `gerente`.
`gerente` se normaliza como `admin` en la app. Para una terminal fija,
aprovisiona una cuenta dedicada con rol `cajero`; no reutilices una cuenta
personal ni asignes el rol desde el cliente. Si el documento o el campo falta,
la app trata la cuenta como cliente. Los usuarios solo pueden editar su correo
y nombre;
las reglas impiden cambiar su propio rol. El propietario asigna el rol en
Firebase Console → Firestore → `users` → documento cuyo ID es el UID de Auth,
verificando antes que el correo corresponda a la persona autorizada. No se usa
un PIN de cliente para elevar permisos. Una vez creado el primer perfil
`admin`, la sección «Personal y permisos» del panel de gerencia permite cambiar
roles de los perfiles listados.
Desde los accesos de gerencia o servicio se puede solicitar una cuenta con
cualquier correo válido al que el solicitante tenga acceso; en «TPV ·
Personal» puede elegir `barista` o `cajero`. Firebase Auth crea la cuenta y
envía el correo de verificación, pero la solicitud queda en
`staffAccessRequests/{uid}` con estado `pending`: solicitar un rol nunca lo
asigna ni permite entrar al POS o al panel. Despliega las reglas Firestore para
permitir solicitudes propias y lectura solo a gerencia. El panel de Gerencia
muestra las solicitudes y permite aprobarlas o rechazarlas; la aprobación
asigna el rol y actualiza el estado de la solicitud en una transacción. Una
solicitud propia que siga `pending` se puede volver a enviar o corregir; esto
no cambia su estado ni concede el rol. Las escrituras de revisión requieren
las reglas Firestore actualizadas con `firebase deploy --only firestore:rules`.
Las solicitudes no son aprobación automática y un usuario no puede asignarse
su propio rol. No se deben compartir contraseñas.

El panel de Gerencia tiene una bandeja interna compartida para comunicaciones
y directrices, con prioridad normal/alta, y una sección separada de Soporte y
Reclamos. Ambas secciones solo están disponibles para cuentas verificadas cuyo
rol en `users/{uid}` sea `admin` o `gerente`. Los mensajes internos se guardan
en `managementMessages`; las reglas permiten leerlos solo a Gerencia y no
permiten editarlos ni borrarlos. Las nuevas reglas de solicitudes y mensajes
internos deben desplegarse antes de usar esas funciones.

El registro de usuarios envía un enlace de verificación de Firebase
Authentication y no abre la app hasta que el correo se confirme. El documento
`users/{uid}` comienza con `isVerified: false`; el cliente no puede cambiar ese
campo. La insignia azul solo aparece después de que una función backend
comprueba que el correo está verificado y que Cloud Vision detectó un rostro y
no encontró categorías SafeSearch de riesgo alto. La opción para tomar una
selfie está disponible en el perfil de clientes y en el TPV para personal
autenticado. La moderación no prueba identidad legal ni que la persona sea
quien aparece en la imagen.

Para habilitar la moderación real de fotos, configura Firebase Storage en el
proyecto y Cloud Vision API con facturación. Guarda la clave de Cloud Vision
como secreto de Functions (restringida a esa API; nunca la pongas en Flutter):

```sh
firebase functions:secrets:set GOOGLE_CLOUD_VISION_API_KEY
firebase deploy --only functions,firestore:rules,storage
```

La función `moderateProfilePhoto` no verifica fotos si el secreto/API o el
bucket no están configurados; en esos casos informa un error y no concede la
insignia. Las reglas de Storage deniegan escrituras directas del cliente; solo
la función guarda la imagen después de moderarla. La llamada callable se
limita a usuarios con sesión y correo verificado.

En iOS/Android, el registro solicita autenticación biométrica cuando el
dispositivo tiene biometría configurada. Es una comprobación local opcional:
no se transmite una plantilla biométrica, no identifica a la persona y no se
ejecuta en Web. Si se generan proyectos móviles nativos, configura
`NSFaceIDUsageDescription` en iOS y usa `FlutterFragmentActivity` más el permiso
`USE_BIOMETRIC` en Android, tal como requiere `local_auth`.

En «OPERACIONES LOCALES», «MEMBER CARD» registra titulares de tarjetas vendidas
en `member_cards` y asigna números `CW-M-######` con un contador transaccional.
El registro requiere personal verificado; nombre, teléfono, CI y correo son
obligatorios. El código de tarjeta se asigna automáticamente y se muestra al
terminar el registro. La colección `customers` y sus documentos existentes se
conservan sin migración. Las reglas permiten leer los datos personales solo a
gerencia y prohíben listar los documentos de búsqueda de tarjeta. Despliega
`firestore.rules` para habilitar este flujo. Las Gift Cards siguen siendo
anónimas e independientes.
La interfaz bloquea las rutas de barista/cajero fuera del TPV, pero un cliente
Flutter no puede demostrar por sí solo que está ejecutándose en un dispositivo
físico autorizado: una cuenta de personal todavía podría autenticarse en otro
teléfono y alcanzar el TPV. Para garantizar el uso exclusivo en el terminal,
se necesita una comprobación de dispositivo gestionada por servidor (por
ejemplo, inscripción/allowlist del terminal y validación backend/App Check);
no se debe confiar en el tamaño de pantalla ni en un secreto incluido en la app.
El acceso al TPV se autoriza por rol en la app. Para restringirlo al terminal
físico del local, además hace falta una validación de dispositivo en backend;
no basta con un flag de compilación de Flutter.
Sin sesión, la app muestra primero el inicio de sesión; desde el mismo formulario
se puede cambiar a creación de cuenta. El registro guarda el username como
nombre de perfil y solicita correo y contraseña; no requiere teléfono ni
verificación por SMS. El inicio de sesión usa correo y contraseña. Para personal,
se mantiene la verificación del correo y el rol autorizado en Firestore. El
rol de cada cuenta de personal se valida en Firestore después de autenticar.
El filtro de lenguaje del username en Flutter mejora la experiencia, pero debe
duplicarse en backend si se usa para moderación o reglas de negocio. En el
formulario y en Mi Perfil se puede tomar una foto con la cámara o elegir una
imagen; en Chrome el usuario debe permitir el acceso a la cámara cuando el
navegador lo solicite. La foto se analiza con Cloud Vision antes de guardarse.
SafeSearch no demuestra que la imagen sea propia ni que no venga de Internet;
eso requiere un control de procedencia y duplicados.
En Firebase Console → Remote Config, crea el parámetro booleano
`mostrar_peluches`, publícalo en `false` para ocultar «Coleccionables» o en
`true` para mostrarla. Como la app web no admite el stream de cambios en tiempo
real de FlutterFire, consulta la configuración cada minuto y
empieza con `false` hasta que Firebase indique lo contrario. Si se desactiva,
también impide abrir los detalles y retira los artículos de esa categoría del
carrito local. Remote Config solo controla la presentación del cliente: no
reemplaza las reglas de autorización del backend ni una validación de stock al
procesar una compra. Los navegadores web no exponen de forma fiable el SSID del
Wi-Fi; no debe usarse una comprobación de SSID en Flutter Web como control de
seguridad.
El QR no completa el álbum por sí solo; para validar escaneos y desbloquear
figuras entre dispositivos se necesita un lector en la app cliente y un backend
con autenticación, caducidad y persistencia.

### Demo local de Gift Cards, coleccionables y automatizaciones

El panel oculto de Barista permite crear Gift Cards con saldo en Bs y códigos
QR únicos durante la sesión. En «Mi perfil → Billetera» se canjea cada código
una sola vez; el saldo de demostración también se puede aplicar al checkout.
«Mis Coleccionables» muestra los seis personajes iniciales, sus IDs
secuenciales (#001, #002, …), los QR y el certificado dorado al reclamar una
pieza. El panel permite registrar piezas adicionales, asignándoles el siguiente
ID.

Las automatizaciones locales muestran el aviso de ausencia tras 14 días sin
completar una visita del pasaporte, el aviso de recogida al marcar como listo el
pedido de muestra y la disponibilidad de productos cambia al instante al
actualizarse desde el panel. El panel incluye una acción de demostración para
probar el aviso de 14 días. Estos datos viven únicamente en memoria: no hay
persistencia entre reinicios ni sincronización o bloqueo de reclamos entre
dispositivos. El lector de QR de coleccionables se simula ingresando el código;
la app no abre la cámara. Los avisos son in-app mientras la instancia está
abierta, no notificaciones push. Para producción se requiere persistencia y
transacciones en backend; los disparadores push requieren además FCM y lógica
de servidor programada.

Wolves Shop tiene cuatro categorías: Moda Alfa, Coleccionables, Accesorios y
Estilo de Vida. Las prendas incluyen existencias separadas para S, M, L y XL,
una guía de talles interactiva y estados Disponible, Agotado y Próximamente.
En productos Wolves Shop persistidos, `stockBySize` (S, M, L y XL) debe sumar
exactamente el campo `stock`. El POS solicita una talla, bloquea las agotadas
y descuenta esa talla junto con el total dentro de la transacción Firestore de
la venta; las reglas impiden al vendedor editar existencias manualmente. Los
artículos locales de demostración siguen siendo temporales y no se pueden
cobrar desde el POS. Solo una cuenta de Gerencia verificada puede editar el
inventario persistido. El ajuste local de demostración se limita a la sesión de
Gerencia de prueba.
El checkout solicita una orden de pago QR dinámica al backend HTTPS configurado
con `WOLVES_PAYMENTS_API_URL`. Flutter envía el importe calculado, líneas del
carrito, token de Firebase e `Idempotency-Key`; muestra el QR de la orden y
consulta su estado cada tres segundos (hasta cinco minutos). Solo la respuesta
`paid` del backend confirma la compra. El backend debe verificar la notificación
del proveedor, recalcular precios y aplicar el descuento de inventario de forma
atómica solo después de confirmar el pago. Para productos con tallas, debe
validar y descontar `size` de `stockBySize` además del total `stock`. También
debe hacer que `POST /orders` sea idempotente. El QR debe ser una URL HTTPS accesible
por el navegador (con CORS si está en otro origen). La app no contiene secretos
del proveedor ni debe marcar un pago como exitoso por datos suministrados por el
cliente.

Contrato HTTP esperado:

```http
POST {WOLVES_PAYMENTS_API_URL}/orders
Authorization: Bearer <Firebase ID token>
Idempotency-Key: <clave única por intento>
Content-Type: application/json
```

```json
{
  "amount": 180,
  "currency": "BOB",
  "items": [
    {
      "productId": "polera-wolves",
      "name": "Polera Wolves Club",
      "size": "M",
      "unitPrice": 180,
      "quantity": 1
    }
  ]
}
```

El backend responde HTTP 200/201 con
`{"orderId":"...","amount":180,"qrImageUrl":"https://...","status":"pending"}`.
La app consulta
`GET {WOLVES_PAYMENTS_API_URL}/orders/{orderId}` con el mismo token; la respuesta
JSON debe contener el mismo `orderId` y `status` (`pending`, `paid`, `failed` o
`expired`). También se aceptan `pendiente`, `exitoso`/`success`/`aprobado`,
`fallido`/`rechazado` y `expirado`/`vencido`, normalizados a esos estados. El
backend debe autorizar al propietario de la orden y solo devolver `paid` o
`exitoso` tras verificar el pago directamente con el proveedor.

Configura la URL al compilar; no pongas tokens ni claves privadas en el
`--dart-define`:

```sh
flutter build web --release \
  --dart-define=WOLVES_PAYMENTS_API_URL=https://api.example.com/payments
```

Para ejecutar el checkout en Chrome durante el desarrollo, usa la misma URL:

```sh
flutter run -d chrome \
  --dart-define=WOLVES_PAYMENTS_API_URL=https://api.example.com/payments
```

El catálogo local de demostración todavía vive en memoria. Los productos
compartidos de Wolves Shop usan documentos Firestore y el POS actualiza su
inventario de forma transaccional. En el checkout remoto, el backend debe
actualizar el inventario compartido tras verificar el pago, incluyendo la talla
seleccionada cuando el artículo tiene `stockBySize`.

La navegación separa «Menú café» (comida y bebidas) de «Wolves Shop» (Moda Alfa,
Coleccionables, Accesorios y Estilo de Vida). La tienda conserva artículos
locales de demostración y también lee los productos compartidos guardados en
Firestore; `firestore.rules` valida el esquema y las operaciones permitidas
sobre esos documentos. El checkout con QR crea órdenes y consulta su estado en
el backend descrito arriba; no confirma cobros basándose en datos locales.

El panel del Barista permite abrir la primera pantalla local de TPV. El turno
mantiene en memoria el perfil de la cuenta autenticada, y las familias
Cold Brew, Brewing, Speciality Coffee, Desserts, Bakery, Hot Drinks, Ice Matcha,
Fríos, Desayuno, Ensaladas, Combos y Pet Friendly filtran el catálogo de café.
El catálogo inicial del TPV incluye los productos humanos y precios de la lista
oficial incorporada en `main.dart`. Los productos Pet Friendly aparecen con
«Consultar precio» hasta que un barista les asigne un precio desde el editor.
Si un producto del menú sincronizado no tiene precio o guarda `0`, la interfaz
usa el precio del catálogo oficial local cuando hay una coincidencia; conserva
el precio de Firestore cuando ya está configurado. El stock sigue viniendo de
Firestore: los artículos con cero existencias no se habilitan para venta hasta
que Gerencia registre las cantidades físicas reales.
Gerencia puede actualizar diariamente precio y existencias del menú desde
«Inventario de consumo»; el mismo módulo permite editar precio, stock y
visibilidad de Wolves Shop, incluido el stock por talle. Los productos con
stock cero o deshabilitados expresamente no se venden.
En «Administrar catálogo TPV», Gerencia puede registrar cuántas unidades saca a
tienda. Al ingresar una cantidad queda activado el control de inventario; cada
venta del TPV la descuenta de forma transaccional. El menú muestra las unidades
disponibles y marca como agotado el producto que llega a cero. Para recibir una
notificación push en el teléfono, Gerencia debe iniciar sesión en un origen
HTTPS, pulsar «Activar notificaciones de faltante» y permitir las notificaciones
en el navegador. La Cloud Function `notifyManagementOnCafeProductOutOfStock`
envía el aviso al cruzar de una cantidad positiva a cero.
Los productos son agregables a la comanda local. El panel de Barista incluye un
administrador de catálogo TPV: permite filtrar por familia, agregar productos,
editar nombre, precio, categoría y descripción, o eliminar artículos. El
TPV ofrece una búsqueda en tiempo real sobre todo el catálogo y una cuadrícula
adaptable con tarjetas compactas que reutilizan `imageAsset` y el mismo
renderizado fotográfico del menú de clientes; los productos sin foto asignada
conservan el marcador visual existente. Los botones sociales muestran marcas
monocromáticas en oro viejo sobre botones circulares oscuros, alineados sobre un
fondo con textura sutil, y abren los perfiles oficiales.
WOLVES MATCH es una función voluntaria independiente del perfil público. Cada
participante verificado y mayor de 18 años elige intención, nombre visible,
biografía e intereses; solo una activación con consentimiento explícito publica
un perfil reducido a otros participantes activos con intención compatible.
Perfiles, recomendaciones, intereses, aceptaciones mutuas, descartes, bloqueos y
reportes usan consultas y transacciones directas de Firestore, protegidas por
reglas que exigen sesión verificada, mayoría de edad declarada, consentimiento
para activar el perfil y pertenencia a cada conexión. Los documentos públicos
de Match no incluyen UID, correo ni teléfono; el cliente y las reglas rechazan
patrones comunes de datos de contacto y ubicación en el nombre y la biografía.
Las reglas deben desplegarse antes de habilitar la versión directa:

```sh
firebase deploy --only firestore:rules
```

La trivia y «¿Qué prefieres?» de Coffee Pup están temporalmente desactivadas:
su validación y las recompensas requieren verificación confiable de servidor y
no se conceden desde el cliente en el plan Spark. Perfiles activos antiguos se
publican en la nueva colección al entrar a Match. Las conexiones históricas no
se migran porque sus documentos contienen UID privados y no se exponen al
cliente. La edad se comprueba usando la fecha declarada en el perfil; esto no
equivale a una verificación legal de identidad o edad.

El radar de WOLVES MATCH es una representación visual animada de los perfiles
compatibles recibidos desde Firestore; no realiza búsquedas geográficas, no
solicita permisos de ubicación y no finge distancias de 5 km. Las burbujas
muestran únicamente iniciales de participantes reales.

La portada y el menú incluyen enlaces
de acción a Facebook, Instagram, TikTok y WhatsApp, tomados del sitio oficial.
El catálogo se comparte con el menú de clientes de esta instancia, pero los cambios
solo viven en memoria y se pierden al reiniciar; no se sincronizan entre
dispositivos ni están persistidos en Firestore. El turno del TPV queda asociado
a la cuenta autenticada, aunque todavía no solicita un PIN de turno. El TPV incluye salida directa a
Inicio, mapa local de ocho mesas con apertura/liberación de comandas y reservas
por pulsación larga, vista previa de impresión y cálculo de cambio con entrada
numérica y botones de billetes. La impresión es solo una simulación; no hay
conexión a impresora. Mesas, reservas y pagos son locales y no persisten.

La pantalla «Nuestra Manada» presenta seis tarjetas responsivas con las imágenes
de `assets/images/wolves/wolf_1.png` a `wolf_6.png`, animación de elevación al
pasar el cursor y una ficha ampliada al tocarlas. Los nombres, cargos, edades y
biografías incluidos son contenido de muestra editable en `main.dart`; deben
confirmarse con los datos oficiales de cada perrito antes de publicar.

### Configurar Firebase para POS y cocina

1. Registra la app para cada plataforma y activa **Authentication → Email/Password**.
   No hace falta habilitar el proveedor Phone. Para Web, agrega el dominio desde
   el que se probará a **Authentication → Settings → Authorized domains**.
   Verifica los correos del personal y asigna el campo `role` en `users/{uid}`
   desde Firebase Console.
   Para identificar los correos de confirmación, abre **Authentication →
   Templates → Email address verification** y edita la plantilla: usa
   `Coffee Wolves` como nombre del remitente, un asunto como
   `Confirma tu correo de Coffee Wolves` y un mensaje que explique que el
   enlace es para verificar la cuenta. Guarda los cambios en Firebase Console.
   Edita también **Authentication → Templates → Password reset** por separado,
   con remitente `Coffee Wolves` y asunto `Restablece tu contraseña de Coffee
   Wolves`; ese enlace cambia la contraseña y no verifica el correo.
   Flutter solo solicita el envío; no puede cambiar el nombre/dirección del
   remitente ni el contenido de esa plantilla. Firebase puede seguir usando
   una dirección técnica `noreply` aunque el nombre visible sea Coffee Wolves.
2. Crea Firestore en modo producción y despliega las reglas incluidas:

   ```powershell
   firebase login
   firebase use --add
   firebase deploy --only firestore:rules
   ```

3. Obtén las dependencias y ejecuta la versión Web usando la configuración
   Firebase ya registrada en `lib/firebase_options.dart`:

   ```powershell
   flutter pub get
   flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
   ```

   En macOS, `0.0.0.0` hace que el servidor escuche por Wi-Fi sin fijar ni
   reemplazar la IP de ninguna red. Para abrirlo desde un teléfono conectado
   al mismo Wi-Fi, usa el nombre local del Mac:

   ```sh
   echo "http://$(scutil --get LocalHostName).local:8080"
   ```

   Ese nombre suele resolver automáticamente a la IP DHCP actual tanto en casa
   como en el trabajo. Si Bonjour (`.local`) no está disponible en una red,
   consulta la IP Wi-Fi actual con `ipconfig getifaddr en0` y abre
   `http://IP_ACTUAL:8080`; la IP puede cambiar al conectarse a otra red, pero
   no hace falta editar ni borrar ninguna IP en el código. El Mac y el teléfono
   deben estar en la misma red y la red debe permitir comunicación entre
   dispositivos; una red de invitados puede bloquearla.

   Firebase Authentication autoriza dominios, no controla a qué Wi-Fi se conecta
   el teléfono. Si el inicio de sesión del navegador rechaza el nombre usado,
   revisa **Authentication → Settings → Authorized domains** y agrega el host
   sin protocolo ni puerto, si Firebase lo acepta. No hay que modificar
   `lib/firebase_options.dart` para cambiar de red. Los orígenes HTTP locales
   pueden no ser contextos seguros para Phone Auth, notificaciones Push o
   service workers; usa Firebase Hosting HTTPS para probar esos flujos.
   Para publicar, usa `flutter build web --release`. POS y cocina deben apuntar
   al mismo proyecto. La app usa el claim del usuario autenticado para dirigir
   clientes al Home, personal al POS y gerencia al panel administrativo.
4. Mantén abierto el panel en el dispositivo de cocina para recibir los cambios
   de Firestore y escuchar el timbre. Para alertas con la PWA cerrada, configura
   Firebase Cloud Messaging siguiendo la sección siguiente.

### Alertas de cocina con la PWA cerrada

El TPV repite el timbre mientras está abierto y una comanda sigue pendiente.
Además, Cloud Messaging envía una notificación push a los dispositivos web
inscritos de baristas/cajeros verificados. La notificación se vuelve a enviar
cada minuto hasta que cocina reconoce la comanda; al reconocerla, la aplicación
actualiza su estado y las notificaciones pendientes se cierran en los
dispositivos que reciban el aviso.
Las notificaciones de faltante del inventario del menú se envían a los
dispositivos registrados por cuentas verificadas de Gerencia.

Para activarlo en producción:

1. En Firebase Console → **Cloud Messaging → Web Push certificates**, genera o
   consulta la clave pública VAPID para la aplicación web.
2. Usa un origen HTTPS, por ejemplo el Hosting de Firebase
   (`https://wolves-club-fb24a.web.app`). El origen HTTP de una IP local como
   `http://192.168.100.6:8080` no es un contexto seguro y no permite Push ni
   service workers en teléfonos. Añade el dominio HTTPS a Authentication →
   Settings → Authorized domains.
3. Instala/abre la PWA en cada dispositivo, inicia sesión con una cuenta de
   personal o Gerencia verificada y activa las notificaciones desde la sección
   correspondiente (**ACTIVAR ALARMA EN ESTE DISPOSITIVO** en cocina o
   **ACTIVAR NOTIFICACIONES DE FALTANTE** en el catálogo). Acepta el permiso de
   notificaciones. Cada dispositivo debe registrarse por separado.
4. Compila la web con la clave pública VAPID (no es una clave privada):

   ```sh
   flutter pub get
   flutter build web --release \
     --dart-define=WOLVES_FCM_VAPID_KEY=CLAVE_PUBLICA_VAPID
   ```

5. Functions Gen 2 y el trabajo programado cada minuto necesitan el plan
   Firebase Blaze y facturación habilitada. Revisa los costos de Cloud
   Functions/Cloud Scheduler y luego despliega explícitamente:

   ```sh
   cd functions && npm install && cd ..
   firebase deploy --only functions,firestore:rules,hosting
   ```

La PWA cerrada depende del sistema de notificaciones del navegador y del
teléfono: el tono es el sonido de notificación configurado en el sistema, no
una reproducción personalizada del WAV. El modo silencio, No molestar,
permisos denegados, ahorro de batería, pérdida de red o restricciones del
navegador pueden silenciar o retrasar avisos; el navegador no permite garantizar
una alarma acústica continua como una app nativa. La repetición del servidor es
cada minuto, no un tono continuo. Para sonido personalizado/continuo y control
de vibración fiable con la app cerrada se necesita una aplicación nativa y sus
permisos/configuración específicos.

### Chat de WOLVES MATCH en el plan Spark

El chat consulta el saldo y guarda los mensajes directamente en
`users/{uid}/chatMessages`; cada envío descuenta el saldo en una transacción
de Firestore. Las reglas exigen que el mensaje y el descuento de un crédito
ocurran juntos; el cliente no puede aumentarse el saldo. Cada cuenta nueva
recibe 10 créditos. El crédito por anuncio se deshabilitó para el chat porque
su verificación segura dependía de Cloud Functions. Al acabarse los créditos
no se aceptan más mensajes.

Si Firestore responde `resource-exhausted` al agotarse la cuota gratuita, la
interfaz pausa los envíos y muestra el error; no reintenta automáticamente.
En Spark, Firestore aplica sus límites gratuitos sin pasar el proyecto a
facturación de pago. Para cuentas creadas antes de estos cambios, se inicializa
una sola vez el saldo al abrir el chat. Despliega `firestore.rules` para que la
escritura directa quede autorizada y protegida.

### Pedidos internos y facturación SIAT

Los mensajes de soporte, sugerencias y reclamos se guardan en
`customerComplaints`. El cliente recibe una respuesta automática dentro de la
app al enviar el caso y puede consultar el historial/estado desde «Mis mensajes
a soporte». Gerencia tiene una sección separada con filtros por tipo, estado y fecha, y
los cambios a «En revisión» o «Resuelto» generan un mensaje visible en el
seguimiento del cliente. No se envían correos automáticamente: el botón
de correo de Gerencia solo abre el programa de correo configurado.

Cada venta del TPV se registra en `cafeSales` y, en la misma transacción que
descuenta el inventario, crea su registro en `pedidos_internos`. Esta colección
guarda los artículos de la venta, datos operativos y el estado de cocina; solo
personal verificado puede leerla. Las comandas con productos de cafetería
empiezan como `pending` y se reconocen desde cocina. Las ventas sin productos
de cafetería quedan `confirmed`. `cafeOrders` se conserva únicamente para
consultar y terminar comandas históricas.

`facturas_siat` está denegada por Firestore Rules a todos los clientes Flutter.
No existe todavía una integración de emisión/transmisión SIAT en este
proyecto. No se generan CUF, CUFD, firmas ni facturas de prueba. Para habilitarla
hace falta un backend controlado que confirme primero el pago con el proveedor
de pagos y la respuesta SIAT; únicamente ese backend, usando Admin SDK y
credenciales/certificados custodiados en servidor, podrá crear la factura
confirmada con CUF, CUFD y firma digital. No se deben enviar credenciales ni
aceptar el estado de pago o datos fiscales declarados por Flutter. Despliega
las reglas actualizadas antes de usar la nueva colección:

```sh
firebase deploy --only firestore:rules
```

El canje Cold Brew usa como ID de auditoría el QR temporal de un solo uso. La
transacción de Firestore marca el registro `delivered` y rechaza cualquier
segundo intento con el mismo QR. Las adopciones de peluches también cambian
atómicamente el estado de autenticidad a `adopted`, y la bitácora del perfil
muestra bloqueados/desbloqueados los modelos oficiales según la propiedad
registrada. La bitácora separa los seis modelos `CW-PLUSH-001` a
`CW-PLUSH-006` bajo **PLUSH** y los modelos **CUPS** `CW-CUP-007`
(POMERANIAN), `CW-CUP-008` (SAMOYED) y `CW-CUP-009` (HUSKY). Sus códigos
individuales siguen el formato `CW-{PLUSH|CUP}-NNN-SSSS`. Se mantienen
válidos los códigos `CW-PLUSH-007` a `CW-PLUSH-009` ya emitidos para preservar
registros existentes. Todas las unidades usan la misma asignación transaccional
de series y verificación pública.

La sección **Mi Bitácora · Mi camino Wolves** reúne el progreso persistido del
Coffee Passport, el álbum Cold Brew, retos y coleccionables. Los retos se
guardan como autodeclarados por el miembro; no validan por sí mismos premios ni
visitas. También muestra el estado de hitos reales del Passport/Cold Brew y
accesos directos a Rewards, Badges, estadísticas, eventos, Member Card, pedidos,
billetera y mascotas. El perfil de usuario solo consulta su propio progreso.
XP y visitas de las pantallas actuales no se guardan todavía, y las insignias
son demostrativas; no se presentan como recompensas verificadas ni como
historial persistido en la bitácora. Si la lectura
de coleccionables devuelve `permission-denied`, publica las reglas Firestore
actualizadas con `firebase deploy --only firestore:rules`; la interfaz muestra
el código real del error y ofrece reintentar sin ocultar los otros módulos.

**Mis Mascotas** guarda perfiles privados en `userPets/{uid}/pets`. Cada perfil
incluye nombre, raza, fecha de nacimiento, descripción y hasta seis fotos
optimizadas en Firebase Storage bajo `pet-profiles/{uid}/...`. El miembro puede
editar o eliminar sus perfiles; las reglas limitan lectura y cambios al dueño
de la cuenta verificada. Despliega ambos grupos de reglas al publicar:
`firebase deploy --only firestore:rules,storage`.

**Legado de la Manada** es una vitrina pública curada por Gerencia, separada
del Coffee Passport y del Muro de las Travesuras. Los perfiles se almacenan en
`packLegacyProfiles`; solo los documentos con `published: true` se muestran a
los miembros. Gerencia puede crear, editar, publicar, retirar y guardar
borradores desde **Promociones, Eventos y Legado**. Cada perfil puede incluir
la historia del miembro y su mascota, logros, reconocimientos y experiencias
especiales. La vitrina comienza vacía: Gerencia agrega contenido real antes de
publicarlo. Para habilitarla en producción, despliega las reglas Firestore
actualizadas con `firebase deploy --only firestore:rules`.

Para registrar métodos del Coffee Passport y canjear la taza de 9/9, la cuenta
debe tener una Wolves Member Card activa (`CW-XXXXXX`). El personal ingresa el
número de tarjeta o el valor codificado en su QR; los UID directos no se
aceptan. La app comprueba el documento de tarjeta y su índice antes de registrar
progreso, y las reglas Firestore vuelven a exigir una tarjeta activa en las
escrituras. El miembro puede abrir **Wolves Member Card** para emitir/ver su
tarjeta y presentar el QR en barra.

El registro requiere una fecha de nacimiento y la guarda en `users/{uid}`.
`saveBirthdayDetails` valida que la fecha exista y que la persona tenga al menos
18 años antes de registrar los campos de mes y día. Las cuentas existentes sin
fecha pueden completarla en Mi Perfil; una fecha ya guardada no se puede editar
desde el cliente. El permiso para una felicitación con invitación promocional
es opcional y revocable. No hay un proveedor de correo promocional configurado,
por lo que guardar el permiso no activa todavía envíos automáticos.

La adopción administrativa cambia en una transacción el estado de inventario
de `IN_STOCK` a `ADOPTED` junto con el registro de adopción, certificado,
verificación pública e historial. Los registros antiguos sin `inventoryStatus`
se consideran disponibles solo si siguen sin titular y su verificación pública
indica `available`; al adoptarlos se les asigna `ADOPTED`. El tono de éxito y la
vibración ocurren después de confirmar la adopción, no al abrir la ficha pública
del QR. Para activar nuevos modelos en producción, despliega las reglas
actualizadas junto con la aplicación: `firebase deploy --only firestore:rules`.
Las bebidas de [Hot Drinks](https://sites.google.com/view/coffeewolves/menu/hot-drinks)
usan las fotos y descripciones publicadas; Chai Latte y Mint Latte conservan el
marcador porque esa página no muestra una foto para esos productos.
Los postres y tortas publicados en
[Desserts](https://sites.google.com/view/coffeewolves/menu/desserts) también
incluyen sus fotografías cuando el producto está disponible en el catálogo.

## HOY NOS FALTA UNO

El espacio comunitario **HOY NOS FALTA UNO** está integrado en la navegación
de Manada y utiliza Flutter, Firebase Authentication y Cloud Firestore. Las
cuentas deben tener correo verificado. Las misiones viven en
`lostPetMissions`, los avistamientos en `lostPetSightings`, los favoritos en
`lostPetFavorites`, las solicitudes privadas de contacto en
`lostPetContactRequests` y las denuncias en `lostPetReports`.

Las publicaciones públicas no guardan correo ni teléfono. La información de
collar/placa y la historia no autorizada del reencuentro se guardan en
`lostPetMissions/{missionId}/private/details`, legible solo por la persona
responsable. Las fotos de una misión se optimizan a JPEG (máximo 200 KB cada
una, hasta tres) y se guardan en documentos separados bajo
`lostPetMissions/{missionId}/photos`; los reportes de avistamiento pueden
incluir una foto optimizada directamente en su documento. Esta opción evita
Firebase Storage y el plan Blaze, pero las imágenes siguen consumiendo cuota de
Firestore y deben considerarse al crecer el volumen.

Los estados disponibles son `active`, `sightings`, `verifying`, `reunited` y
`closed`. Una historia de reencuentro solo se muestra en **VOLVIÓ A CASA**
cuando la persona responsable marca expresamente su autorización. Las pistas
se etiquetan como no verificadas; las sugerencias de relación no confirman que
sea el mismo animal. Los reportes de publicaciones solo son legibles por
Gerencia en Firestore; no hay todavía una bandeja administrativa dentro de la
app. Los mensajes privados se consultan en **MIS MENSAJES** o en la ficha de la
misión; no hay un proveedor de notificaciones push configurado, por lo que no
se envían avisos fuera de la app.

Los enlaces compartidos abren la misión directamente en la versión web de
GitHub Pages mediante `?module=lost-pet&mission={id}` después de iniciar sesión.
En plataformas móviles, WhatsApp comparte el resumen y el identificador, pero
no se ha configurado un enlace universal/app link. Publica las reglas nuevas
antes de habilitar el módulo:

```sh
firebase deploy --only firestore:rules
```

No se necesita índice compuesto adicional para los filtros iniciales. Las
consultas de feed están limitadas a 50 documentos; para crecer, deberá añadirse
paginación y una política de retención aprobada. Este espacio facilita
información comunitaria: no es un servicio de rescate ni garantiza recuperar
mascotas.
Las bebidas de [Presurizados y Destilados](https://sites.google.com/view/coffeewolves/menu/presurizados-y-destilados)
incluyen sus fotos y descripciones publicadas. Las cartas que solo están
disponibles como láminas no se reutilizan como fotografías; el resto de las
fichas mantiene un marcador hasta tener una imagen real asignable en el campo
`imageAsset`.
Los productos de [Bakery](https://sites.google.com/view/coffeewolves/menu/bakery)
incluyen sus fotos y descripciones publicadas cuando están disponibles en el
catálogo; se conservan los precios existentes, ya que esa página no los publica.

El Coffee Passport sigue los diez métodos descritos en
[La Experiencia](https://sites.google.com/view/coffeewolves/la-experiencia):
Espresso, Dripper V60, Chemex, Origami, Aeropress, Prensa francesa, Sifón
japonés, Sifón belga, Cold Brew y Nitro Cold Brew. Las fichas muestran el
perfil de la manada y las características publicadas para cada método.

Los productos pet friendly y las bebidas de Presurizados y Destilados se
muestran sin precio porque sus páginas no publican importes; se consulta
disponibilidad y precio por WhatsApp. La app muestra los precios de la carta en
Bs, tomando como referencia la
ubicación y el teléfono boliviano publicados por Coffee Wolves.
