# Publicar connecTO para que se descargue

Plan para más adelante. Hoy no hay un Release: el repo está en `https://github.com/Foodhy/connecTO` y en esta Mac solo hay certificados **Apple Development**. Con esos certificados la app corre en tus equipos. En el de otra persona, macOS la bloquea.

Para copiarla a otra Mac tuya sin certificados, los comandos están en [pasar-a-otro-mac.md](pasar-a-otro-mac.md).

Versión actual: **1.0** (build 1). Equipo de firma: `7RL3XVY7RJ`.

| App | Esquema | Bundle ID | Se puede bajar de GitHub |
| --- | --- | --- | --- |
| Mac, barra de menú | `connecTOMac` | `com.wontsleep.connecTOMac` | Sí, firmada con Developer ID y notarizada |
| iPad / iPhone | `connecTO` | `com.wontsleep.connecTO` | No. Un `.ipa` descargado no se instala |

La del iPad sale por TestFlight o la App Store. Las dos usan la cuenta de pago de Apple Developer.

## Qué hace falta antes del primer Release

1. Cuenta de **Apple Developer Program** (la de pago).
2. Certificado **Developer ID Application** en el llavero de esta Mac. Hoy `security find-identity -v -p codesigning` solo lista `Apple Development`.
3. `gh` autenticado contra `Foodhy/connecTO` (`gh auth status`).
4. El código que se va a etiquetar ya está en `main` y empujado. El README y `assets/hero.png` tienen que ir en ese commit si el Release debe coincidir con lo que se lee en el repo.

`connecTOMac` ya tiene **Hardened Runtime** activado y el sandbox desactivado. La notarización lo exige así: el runtime endurecido es obligatorio, y el sandbox se lleva mal con Accesibilidad y con la captura de pantalla.

Para TestFlight o la App Store, además:

- El icono de iOS está en `connecTO/Assets.xcassets/AppIcon.appiconset` (1024×1024, también en oscuro y tintado).
- `connecTO/PrivacyInfo.xcprivacy` declara que la app no rastrea ni recoge datos. UserDefaults solo guarda datos de la propia app (CA92.1): el identificador del iPad, el último Mac y el tamaño de la imagen.

Esos dos puntos no bloquean el zip del Mac.

## La app del Mac

El resultado es un zip en el Release. El archivo que se instala es ese zip, el que se comprime después de grapar el ticket. El `.app` que deja **Run** en DerivedData queda firmado con Apple Development y macOS lo bloquea en otra Mac.

Quien abre la app no ve un icono en el Dock: `LSUIElement` la deja solo en la barra de menú. En cada Mac hay que activar Accesibilidad, Grabación de pantalla y Red local. Los pasos están en [Instalarla en cada Mac](#instalarla-en-cada-mac).

### 1. Certificado

En [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates) crea **Developer ID Application**, bájalo e instálalo. Comprueba que aparece:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 2. Archivar

Desde la raíz del repo:

```bash
xcodebuild archive \
  -project connecTO.xcodeproj \
  -scheme connecTOMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/connecTOMac.xcarchive
```

`build/` ya está en `.gitignore`.

### 3. Exportar con Developer ID

`ExportOptions.plist` no se sube con secretos; solo lleva el método y el equipo:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>7RL3XVY7RJ</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
```

```bash
xcodebuild -exportArchive \
  -archivePath build/connecTOMac.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

Si la firma automática no encuentra el certificado Developer ID, Xcode → Settings → Accounts → el equipo `7RL3XVY7RJ` → Manage Certificates, y descarga **Developer ID Application**.

### 4. Notarizar y grapar

Guarda las credenciales una vez en el llavero. No las pongas en el repo ni en el workflow en claro:

```bash
xcrun notarytool store-credentials connecto-notary \
  --apple-id "TU_APPLE_ID" \
  --team-id 7RL3XVY7RJ \
  --password "CONTRASEÑA_DE_APP"
```

La contraseña es una de app en [account.apple.com](https://account.apple.com), no la contraseña normal.

```bash
ditto -c -k --keepParent build/export/connecTOMac.app build/connecTOMac-notarize.zip

xcrun notarytool submit build/connecTOMac-notarize.zip \
  --keychain-profile connecto-notary \
  --wait

xcrun stapler staple build/export/connecTOMac.app
xcrun stapler validate build/export/connecTOMac.app
```

Si `--wait` termina en `Invalid`, el detalle está en:

```bash
xcrun notarytool log <id-de-la-respuesta> --keychain-profile connecto-notary
```

No publiques el zip hasta que `stapler validate` diga que el ticket está grapado. Vuelve a comprimir **después** de grapar; el zip enviado a Apple no lleva el ticket.

```bash
ditto -c -k --keepParent build/export/connecTOMac.app build/connecTOMac.zip
```

### 5. Crear el Release

El tag tiene que ser el mismo número que `MARKETING_VERSION`.

```bash
gh release create v1.0.0 build/connecTOMac.zip \
  --repo Foodhy/connecTO \
  --title "connecTO 1.0.0" \
  --notes "$(cat <<'EOF'
## Mac
- Adjunto: connecTOMac.zip. Se abre desde la barra de menú, no desde el Dock.
- La primera vez: Accesibilidad, Grabación de pantalla y Red local, desde el menú de connecTO.

## iPad
Esta versión no incluye la app del iPad. Se instala por TestFlight.
EOF
)"
```

La descarga queda en `https://github.com/Foodhy/connecTO/releases/latest`.

Para la siguiente versión sube `MARKETING_VERSION` y `CURRENT_PROJECT_VERSION` en los dos targets del `pbxproj` (hoy los dos están en 1.0 / 1), etiqueta `v1.0.1` o `v1.1.0`, y repite el archivo. No reutilices un tag.

### Lo mismo desde el Organizer

La primera vez se puede hacer sin la terminal. El zip que se reparte sigue siendo el de después de grapar.

1. Esquema **connecTOMac**, destino **Any Mac**.
2. **Product → Archive**.
3. Organizer → **Distribute App → Developer ID → Upload**.
4. Cuando la notarización termina, exporta `connecTOMac.app`.
5. Si el export no grapó el ticket, usa `xcrun stapler staple` y `stapler validate` como en el paso 4, y vuelve a comprimir con `ditto`. El zip que se subió a Apple no es el que se entrega.

## Instalarla en cada Mac

Cada Mac hace esto una vez, con el zip grapado:

1. Descomprimir y mover `connecTOMac.app` a `/Applications`.
2. Abrirla. Si macOS la detiene la primera vez: **Ajustes del Sistema → Privacidad y seguridad → Abrir de todos modos**.
3. Conceder estos tres permisos, desde el icono de la barra o desde **Ajustes del Sistema → Privacidad y seguridad**:
   - **Accesibilidad.** Sin esto el Mac ignora el puntero, los clics y el teclado.
   - **Grabación de pantalla.** Sin esto el iPad no muestra el escritorio y se queda en el trackpad. Si la imagen no aparece después de activarla, cerrar la app y volver a abrirla.
   - **Red local.** Es lo que deja que el iPad encuentre el Mac (`_connecto._tcp`).
4. El iPad y el Mac tienen que estar en la misma Wi-Fi. El código de 6 dígitos sale en el menú, bajo **Código**, y dura 3 minutos. **Nuevo código** lo reemplaza. **Olvidar iPads** borra `~/Library/Application Support/connecTO/trusted-devices.json`.

Un iPad controla ese Mac a la vez. La app del iPad no va dentro de este zip: se instala por TestFlight.

Esos tres permisos viven en ese Mac y van atados a la firma. Otra firma, u otro certificado, vuelve a pedirlos.

En Mac supervisadas (Jamf, Mosyle, Apple Business Manager) un perfil de privacidad puede preaprobar Accesibilidad y Grabación de pantalla para `com.wontsleep.connecTOMac`, con el designated requirement del certificado Developer ID. Red local sigue pidiendo confirmación en el Mac.

La Mac App Store no es el canal de esta app. Exige sandbox, y `connecTOMac` lo tiene apagado porque publica eventos del teclado y del mouse y captura la pantalla. La distribución es Developer ID.

## La app del iPad

No se adjunta un `.ipa` al Release. Quien lo descargue no puede instalarlo.

Cuando el icono y el manifiesto de privacidad existan:

1. Esquema **connecTO**, destino **Any iOS Device**.
2. **Product → Archive**.
3. Organizer → **Distribute App → App Store Connect → Upload**.
4. En App Store Connect, esa build pasa a TestFlight. Ahí se agregan los testers.

El iPad y el Mac del mismo Release tienen que ser la misma `MARKETING_VERSION`. El protocolo rechaza la sesión si las dos apps no hablan la misma versión.

## Más adelante, en GitHub Actions

Se puede automatizar el archivo del Mac en un workflow que corra al empujar un tag `v*`. Los secretos son el certificado Developer ID (exportado como `.p12`), su contraseña, y el perfil `notarytool`. Nada de eso va al repo.

No vale la pena armar ese workflow hasta que el archivo a mano, en esta Mac, notarice y grabe sin errores. El primer intento es el que enseña qué exige el log de Apple.
