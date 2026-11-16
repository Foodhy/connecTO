# connecTO en Windows

`connecTOWin` es el anfitrión de Windows. Vive en la bandeja (el icono junto al reloj), anuncia `_connecto._tcp` y habla el mismo protocolo que `connecTOMac`. El iPad no se reescribe: ve el PC en la lista y lo controla.

El código está en `connecTOWin/`. El contrato que no se puede romper está más abajo.

## Instalarlo en el PC

Hace falta el SDK de .NET 8. Se puede publicar desde el Mac: el resultado es un programa de Windows, no hace falta compilar en el PC.

En la raíz del repo:

```bash
dotnet publish connecTOWin/connecTOWin.csproj -c Release -r win-x64 --self-contained true -o connecTOWin/Install/payload
```

Eso deja `connecTOWin.exe` y el resto de archivos en `connecTOWin/Install/payload`. Copia la carpeta `connecTOWin/Install` al PC (tiene que incluir `payload` y `install.ps1`). En el PC, en PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File connecTOWin\Install\install.ps1
```

El script hace cuatro cosas:

1. Copia el programa a `%LocalAppData%\Programs\connecTO`.
2. Lo registra para que arranque al iniciar sesión (`HKCU\...\Run`, valor `connecTO`).
3. Pide permiso de administrador y crea la regla de firewall `connecTO`, solo en redes privadas.
4. Lo abre. El icono aparece en la bandeja, no como un botón anclado en la barra.

Si Windows pregunta por el control de cuentas, acepta. Sin esa regla el iPad no llega al puerto TCP.

Para quitarlo:

```powershell
powershell -ExecutionPolicy Bypass -File connecTOWin\Install\uninstall.ps1
```

Cierra el proceso, borra el arranque, la regla de firewall y la carpeta de `%LocalAppData%\Programs\connecTO`.

## Usarlo

1. El PC y el iPad en la misma Wi-Fi.
2. En el PC, pulsa el icono de la bandeja. Ondas: espera. Un iPad: hay un dispositivo enlazado.
3. El panel muestra el código de 6 dígitos, agrupado de tres en tres. Dura 3 minutos y se reemplaza solo. **Nuevo código** lo cambia antes.
4. En el iPad, toca el nombre del PC. El anuncio lleva `plat=win`, así que el botón dice **Controlar el PC** y no ofrece **Monitor externo**.
5. Escribe los 6 dígitos. A la sexta cifra se envían solos.

La siguiente vez, un iPad ya de confianza entra sin código. **Olvidar iPads** borra `%AppData%\connecTO\trusted-devices.json` y genera otro código.

El panel dice si la captura y el cursor están activos. Una línea avisa de que el cursor y el teclado no entran en ventanas de administrador. Si falta la regla de firewall, el botón **Abrir el firewall** la pide otra vez.

**Salir** cierra el programa. Al volver a iniciar sesión arranca solo.

## Qué no hace

El monitor virtual del Mac (`extend`, `CGVirtualDisplay`) no existe aquí: en Windows haría falta un driver de pantalla firmado. Si aun así llega un `role` con `extend`, el PC sigue mostrando el monitor real y el panel lo dice.

Una sola instancia. Un iPad a la vez. Solo la red local. No hay cuenta.

## Comprobar el protocolo sin un PC

En el Mac, con el SDK de .NET 8:

```bash
dotnet test connecTOWin.Tests/connecTOWin.Tests.csproj
```

Esos tests cubren los mensajes, el emparejado, el vídeo y la traducción de teclas. La captura DXGI, el H.264 y `SendInput` solo se ven en el PC.

## Dónde está cada cosa

| Qué | Dónde |
| --- | --- |
| Bandeja y panel del código | `connecTOWin/App.axaml.cs`, `StatusWindow.axaml` |
| Código, confianza, anuncio | `connecTOWin/Host/WindowsHost.cs`, `Net/MdnsAdvertiser.cs`, `Net/SessionServer.cs` |
| Mensajes y emparejado | `connecTOWin/Protocol/` |
| Pantalla y H.264 | `connecTOWin/Capture/` |
| Cursor y teclas | `connecTOWin/Input/SendInputSink.cs` |
| Sonido | `connecTOWin/Audio/WasapiLoopback.cs` |
| El iPad reconoce el PC | `connecTO/Networking/MacBrowser.swift` lee el TXT `plat=win` |

El anuncio mDNS lo hace el propio programa. No hace falta instalar Bonjour de Apple.

## El contrato

Versión del protocolo: `1`. Todo es red local. Un iPad controla el equipo a la vez.

### Descubrimiento

El iPad busca `_connecto._tcp` con TCP. El PC publica ese tipo, el nombre del equipo y el TXT `plat=win`, en el puerto que abre al arrancar.

### Dos conexiones TCP

1. **Control.** La primera. Mensajes JSON con un prefijo de longitud.
2. **Vídeo.** La segunda, solo después de emparejar. El iPad manda `videoHello` con el mismo `deviceID`. A partir de ahí el PC manda imagen y, si se pidió, audio.

Una tercera conexión se cierra. Un `videoHello` con otro `deviceID` cierra el vídeo.

### Mensajes de control

Cada mensaje es `4 bytes de longitud` (entero sin signo, big-endian) y después un JSON de hasta 8192 bytes. El campo `type` es estable.

El iPad manda:

| `type` | Campos | Qué hace el PC |
| --- | --- | --- |
| `hello` | `deviceID`, `deviceName`, `protocolVersion` | Si la versión no es 1, `rejected` / `unsupportedVersion`. Si el iPad es de confianza, abre la sesión. Si no, `needCode`. |
| `pair` | `code`, `deviceID`, `deviceName` | Código de 6 dígitos, 3 minutos. Mal: `rejected` / `badCode`. Vencido: `rejected` / `expiredCode`. Bien: lo guarda y abre la sesión. |
| `pointer` | `dx`, `dy` | Mueve el cursor en relativo, con la misma curva de ganancia que el Mac. |
| `button` | `button` (`left` o `right`), `phase` (`down` o `up`) | Clic. |
| `scroll` | `dx`, `dy` | Rueda. |
| `key` | `keyCode`, `phase`, `modifiers` | Tecla. `keyCode` es el código virtual de macOS. El PC lo traduce. |
| `text` | `text` | Texto, incluidos acentos, como Unicode. |
| `media` | `action`: `volumeUp`, `volumeDown`, `mute`, `playPause`, `next`, `previous` | `VK_VOLUME_*` y `VK_MEDIA_*`. |
| `cursor` | `x`, `y` | Punto del vídeo, de 0 a 1, origen arriba a la izquierda. |
| `quality` | `longSide` | Lado largo. El iPad pide entre 960 y 3840. El PC acepta de 960 a 8192. Por defecto 1920. |
| `screen` | `displayID` | Cambia de monitor. En `extend` se ignora. |
| `audio` | `enabled` | `true`: el sonido va al iPad y se silencia la salida del PC. `false`: vuelve el volumen que había. |
| `role` | `mode`: `control` o `extend` | `control` muestra un monitor que el PC ya tiene. `extend` no crea pantalla: sigue el monitor real. |
| `ping` |  | Responde `pong`. |

El PC manda, por el control:

| `type` | Campos |
| --- | --- |
| `needCode` |  |
| `paired` | `session` (UUID) |
| `rejected` | `reason`: `badCode`, `expiredCode`, `unsupportedVersion`, `notPaired` |
| `pong` |  |
| `screenUnavailable` | No se puede capturar. El iPad pasa a trackpad. |
| `displays` | `displays`: `{ id, name, width, height }`. `active`: el monitor que se envía. El principal va primero. |
| `audio` | `enabled: false` si el iPad pidió sonido y el PC no puede enviarlo. |

`deviceID` y `session` viajan como texto de UUID.

Hasta que la sesión está `paired`, `pointer`, `button`, `scroll`, `key`, `text`, `media`, `cursor`, `quality`, `screen`, `audio` y `role` se responden con `rejected` / `notPaired`.

La captura no empieza hasta que llegaron `role` y `videoHello`, igual que en el Mac.

### Vídeo y audio

La segunda conexión usa otro encuadre. Cada paquete es `4 bytes de longitud` (big-endian) y un cuerpo de hasta 2 000 000 bytes. El primer byte del cuerpo dice el tipo:

| Byte | Resto |
| --- | --- |
| `1` | Formato H.264. `width` uint16, `height` uint16, cantidad de parameter sets uint16. Cada set: longitud uint32 y los bytes del SPS o PPS, sin código de inicio. |
| `2` | Un frame. El byte siguiente es `1` si es keyframe. Después, los NAL con prefijo de longitud de 4 bytes (AVCC). No Annex-B. |
| `3` | Formato de audio. 7 bytes en total: sample rate uint32 y canales uint16. |
| `4` | PCM de 16 bits, intercalado, little-endian. |

Los enteros de estos paquetes van en big-endian. H.264 Main, sin B-frames, 30 fps, keyframe cada 60 frames. El lado largo se escala manteniendo la proporción y redondeando a par. La fórmula del bitrate es la de `ScreenCapturer.bitRate`. Si la captura falla, el control manda `screenUnavailable` y se cierra el vídeo.

El audio sale del loopback WASAPI y se convierte a PCM de 16 bits. La frecuencia y los canales son los de la mezcla del PC, anunciados en el paquete `3`.

### Teclas

Los `keyCode` son códigos virtuales de macOS (`Shared/KeyMapping.swift` y `SpecialKey`). La tabla HID → código de Mac → tecla de Windows está en `connecTOWin/Protocol/KeyTranslation.cs`. El iPad no cambia.

`modifiers` es un entero: command `1`, option `2`, shift `4`, control `8`. En el PC, command y control se vuelven Ctrl (así ⌘C copia). Option se vuelve Alt. Shift se queda en Shift.

**Anterior** y **Siguiente** mandan Control y una flecha. En el PC eso es Win+Ctrl+flecha, que cambia de escritorio virtual. **Ventanas** (Control y flecha arriba, y otra vez abajo) abre la vista de tareas con Win+Tab.
