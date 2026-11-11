# Caja Scanner (Flutter · Android + iOS)

App **offline-first** para registrar pedidos, proveedor y líneas de cajas escaneando códigos de barras.

## Arranque

```bash
flutter create . --org com.tuempresa --project-name caja_scanner   # genera android/ e ios/
flutter pub get
flutter run
```

> `flutter create .` respeta `lib/` y `pubspec.yaml` ya existentes.

## Permisos de cámara

**Android** – `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
```
Y en `android/app/build.gradle`: `minSdkVersion 23` (o superior).

**iOS** – `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Se usa la cámara para escanear códigos de barras.</string>
```
Y en `ios/Podfile`: `platform :ios, '15.5'` (o superior).

## Arquitectura modular

```
lib/
  main.dart
  core/
    db/        app_database.dart, models.dart   (SQLite local, fuente de verdad)
    sync/      sync_service.dart                (cola de pendientes + RemoteApi)
  features/
    scanner/   scanner_page.dart                (módulo reutilizable de cámara)
    grai/      grai_parser.dart                 (extrae el trozo → modelo)
    capture/   capture_form_page.dart, capture_list_page.dart
```

Cada feature depende solo de `core/`; el escáner no sabe nada del negocio.

## Funcionamiento

1. **Pedido**: se escribe o se escanea.
2. **Proveedor**: se elige de los datos maestros. Se autorrellena (pedido ya conocido → su proveedor; si no, el último usado) y el usuario puede cambiarlo. Si el que busca no existe, puede crearlo en el momento.
3. **Líneas** (modelo + cantidad):
   - **Manual**: producto (se elige de los datos maestros) y cantidad.
   - **Escanear GRAI**: se lee el EAN que va dentro del GRAI, se busca entre los productos de los datos maestros y se rellena el modelo. Si el EAN no está, el usuario elige (o crea) el modelo al que corresponde y queda asociado para siempre.
4. Todo se guarda en SQLite junto con la **fecha/hora del escaneo** (`scanned_at`, UTC) y estado `pending`.
5. Al detectar conexión (o con el botón de sincronizar) se envían las capturas pendientes y pasan a `synced`.

## Pantalla de ajustes (icono de engranaje)

Todo se guarda en la tabla local `settings` y se aplica sin recompilar.

**Lectura del GRAI**
- El producto se identifica por su **EAN**, que va dentro del GRAI: `8003` + `0` + EAN (13 dígitos) + nº de serie. Ejemplo: `8003 0 8714548186004 7004946272` → EAN `8714548186004`, serie `7004946272`. Este es el formato de EPS; otros propietarios (p. ej. IFCO) pueden codificar el modelo de otra forma.
- Campo de prueba: pegas un GRAI y ves el EAN, la serie y el modelo que saldría.

**Datos maestros** (también con el icono de la caja en la lista de capturas)
- **Proveedores**: lista de nombres. Añadir, renombrar y borrar.
- **Productos**: nombre del modelo y, opcionalmente, su EAN (se valida el dígito de control). Un producto sin EAN solo se puede usar a mano.
- Son las únicas opciones que se pueden elegir al capturar; desde el selector también se puede crear uno nuevo al vuelo.
- Borrar un dato maestro no cambia las capturas ya guardadas.
- Con API, `GET {url}/catalogs` puede devolver `{"models": {"8714548186004": "Nombre"}, "suppliers": ["Proveedor"], "orderSuppliers": {"pedido": "Proveedor"}}` y se fusiona con lo local.

**Envío de datos** (selector Ninguno / API / Email)
- **API**: URL base y token opcional. Se envía automáticamente al recuperar la conexión. Endpoints esperados: `POST {url}/captures` (idempotente por `id`) y `GET {url}/catalogs`. Adáptalos en `HttpRemoteApi`.
- **Email**: dirección de destino. Al pulsar sincronizar se genera un CSV con las capturas pendientes y se abre la app de correo con el borrador y el adjunto listos. Las capturas se marcan como enviadas al abrir el borrador (la app no puede saber si el usuario llega a pulsar enviar).

### Permisos extra para el envío por email

- **Android** (`AndroidManifest.xml`, dentro de `<manifest>`):
  ```xml
  <queries>
    <intent>
      <action android:name="android.intent.action.SENDTO"/>
      <data android:scheme="mailto"/>
    </intent>
  </queries>
  ```
- **iOS** (`Info.plist`):
  ```xml
  <key>LSApplicationQueriesSchemes</key>
  <array><string>mailto</string></array>
  ```
  En un simulador iOS no hay app de correo configurada; prueba en dispositivo real.

## Pendiente de tu lado

- **Formato exacto de la API** (rutas, autenticación, campos) y, si usas email, el formato de CSV que necesite quien lo recibe.
- **Origen del autorrelleno de proveedor.** Ahora sale de una tabla local `order_suppliers` que se llena con capturas previas o con los catálogos del servidor.

## Compilación en GitHub Actions

El workflow `.github/workflows/build.yml` compila en cada push a `main`, en cada pull request y manualmente (pestaña **Actions → Build → Run workflow**).

- **Android**: genera un APK instalable (`scannapp-android-apk`), firmado con la clave de depuración.
- **iOS**: compila sin firma (`scannapp-ios-unsigned`). Comprueba que el código compila, pero no es instalable en un iPhone; para eso hacen falta certificado y perfil de Apple Developer.

Las carpetas `android/` e `ios/` se generan en CI con `tool/bootstrap_platforms.sh`, que además aplica el permiso de cámara, el `mailto` del envío por email y las versiones mínimas (Android 23, iOS 15.5). Si generas esas carpetas en local y las subes al repositorio, el script respeta lo que ya exista.

## Descargar la app (Android)

Ve a la sección **Releases** del repositorio y descarga el archivo `scannapp-vX.Y.Z.apk` de la última versión. Al instalarlo, Android pedirá permitir instalar apps de orígenes desconocidos. El APK está firmado con la clave de depuración, así que Android puede avisar de que no viene de Google Play.

Para publicar una versión: en GitHub, **Actions → Build → Run workflow**, escribe la etiqueta (por ejemplo `v1.0.0`) en *release_tag* y ejecútalo. También se publica sola al subir una etiqueta `v*` con git. En ambos casos el workflow compila y adjunta el APK a la release. Antes de una versión nueva, sube `version` en `pubspec.yaml`.
