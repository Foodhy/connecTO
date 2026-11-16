# Pasar connecTOMac a otra Mac

Para una Mac tuya, sin certificado de pago, sin Developer ID y sin notarización. El resultado es `~/Desktop/connecTOMac.zip`. La otra Mac tiene que ser macOS 15 o posterior. El binario sale universal (`x86_64` y `arm64`).

Esto no sustituye un Release público. Para Developer ID y notarización, el plan está en [release.md](release.md).

## En esta Mac

Desde la raíz del repo:

```bash
xcodebuild -scheme connecTOMac -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/connecTO-dd build

codesign --force --deep --sign - \
  /tmp/connecTO-dd/Build/Products/Release/connecTOMac.app

ditto -c -k --keepParent \
  /tmp/connecTO-dd/Build/Products/Release/connecTOMac.app \
  ~/Desktop/connecTOMac.zip
```

`codesign` responde `replacing existing signature`. Eso quita la firma Apple Development y deja una firma local, que no depende de qué Macs estén registradas en el equipo.

El aviso `No App Category is set` no impide el build.

Pasa `connecTOMac.zip` por AirDrop, USB o como quieras.

## En la otra Mac

La Terminal no puede escribir en `/Applications`, ni con `sudo` (`Operation not permitted`). Descomprime en el Escritorio:

```bash
ditto -x -k ~/Downloads/connecTOMac.zip ~/Desktop
xattr -dr com.apple.quarantine ~/Desktop/connecTOMac.app
open ~/Desktop/connecTOMac.app
```

Si el zip no está en Descargas, cambia esa ruta. Si más tarde la quieres en `/Applications`, arrástrala desde el Finder.

La app no abre ventana: `LSUIElement` la deja en la barra de menú. La primera vez concede estos tres permisos, desde el menú de connecTO o desde **Ajustes del Sistema → Privacidad y seguridad**:

- **Grabación de pantalla.** Sin esto el iPad no muestra el escritorio.
- **Accesibilidad.** Sin esto el Mac ignora el puntero, los clics y el teclado.
- **Red local.** Es lo que deja que el iPad encuentre el Mac.

Si Gatekeeper la bloquea después de quitar la cuarentena, en **Ajustes del Sistema → Privacidad y seguridad** aparece **Abrir de todos modos**.

Esos permisos viven en esa Mac y van atados a la firma. Volver a firmar y copiar de nuevo vuelve a pedirlos.
