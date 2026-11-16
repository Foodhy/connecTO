# Fuera de la red local

Plan para más adelante. Hoy el iPad y el Mac tienen que estar en la misma Wi-Fi. Este documento es cómo llegar a tu Mac desde otra red, con el protocolo que ya existe, sin abrir un puerto en el router de casa.

## Cómo está hoy

1. `connecTOMac/SessionServer.swift` abre `NWListener(using: .tcp)` y anuncia `_connecto._tcp`. El puerto lo elige el sistema en cada arranque.
2. `connecTO/Networking/MacBrowser.swift` busca ese tipo con `NWBrowser` y arma un `DiscoveredMac` cuyo `endpoint` es el servicio Bonjour.
3. `SessionClient.connect(to:)` abre la conexión de control contra ese endpoint. Tras `paired`, `openVideo` abre una segunda conexión TCP al mismo endpoint. Una tercera se cierra.
4. `RootView` llama a `reconnectIfNeeded` cuando cambia la lista. Esa función solo reconecta si `connecTO.lastMacName` vuelve a aparecer entre los resultados de Bonjour.
5. Con la lista vacía, `DiscoverView` dice que el Mac tiene que estar en la misma Wi-Fi.

Bonjour es mDNS. No sale del segmento de red. Desde otra Wi-Fi, o por datos del iPad, la lista queda vacía y no hay endpoint al que marcar.

El protocolo sigue en claro y el primer emparejamiento es un código de 6 dígitos. La confianza queda en el Mac, en `~/Library/Application Support/connecTO/trusted-devices.json`.

## La red

Tailscale en el Mac y en el iPad. Los dos entran en una red WireGuard con direcciones `100.x`. El camino va cifrado y el router de casa no reenvía ningún puerto.

El Mac tiene que estar despierto y con Tailscale conectado. En el iPad, Tailscale es la VPN activa: si hay otra VPN delante, el tráfico hacia `100.x` no entra en ese túnel. Grabación de pantalla y Accesibilidad siguen haciendo falta, igual que en la red local.

Bonjour no se ve al otro lado del túnel. La app tiene que poder marcar un host y un puerto. El nombre a copiar sale del menú de Tailscale (el nombre MagicDNS o la IP `100.x`).

## Fase 1 — Puerto fijo en el Mac

Objetivo: el listener escucha siempre en el mismo puerto, y el menú lo enseña. La lista Bonjour de la red local sigue funcionando.

En `SessionServer.start`, el listener pasa a `NWListener(using: .tcp, on:)` con el puerto `47777`. El número vive en una constante de ese archivo. `NWListener.Service(type: "_connecto._tcp")` se queda: Bonjour publica ese puerto y el iPad de la misma Wi-Fi no tiene que escribir nada.

`MenuStatusView` muestra el puerto junto al estado del enlace, para copiarlo al lado del nombre que da Tailscale.

Si el puerto está ocupado, `start()` falla como hoy y `restart()` vuelve a intentarlo.

Prueba de cierre: en la misma Wi-Fi, el iPad sigue encontrando el Mac y controlándolo. El menú del Mac muestra `47777`.

## Fase 2 — Marcar host y puerto en el iPad

Objetivo: desde otra red, la persona escribe la dirección y entra en la misma sesión.

`DiscoveredMac` ya guarda un `NWEndpoint`. Una dirección a mano se arma con `NWEndpoint.hostPort(host:port:)` y un `id` del estilo `host:puerto`. El puerto por defecto del campo es `47777`.

`DiscoverView` ofrece esa entrada además de la lista. Al confirmar, sale el mismo diálogo de **Controlar el Mac** y **Monitor externo**, y `RootView` llama a `SessionClient.connect(to:mode:)` como con un Mac de Bonjour. La conexión de vídeo reutiliza el endpoint guardado, así que las dos TCP salen hacia esa dirección. El protocolo no cambia: `ProtocolVersion.current` se queda en 1.

El texto de lista vacía sigue hablando de la Wi-Fi para el descubrimiento automático, y al lado queda la acción de escribir una dirección.

Prueba de cierre: iPad en otra red, Tailscale conectado en los dos, se escribe el nombre del Mac y `47777`. El código (o la confianza ya guardada) abre la sesión, se ve el escritorio y el puntero llega al Mac. En la Wi-Fi de casa, la lista Bonjour sigue abriendo la sesión sin escribir la dirección.

## Fase 3 — Volver a entrar solo

Objetivo: al reabrir la app lejos de casa, el iPad marca la última dirección sin esperar a Bonjour.

`reconnectIfNeeded` hoy exige que el nombre esté en `browser.macs`. Una sesión manual no reaparece ahí.

Al quedar `paired` por una dirección escrita a mano, se guardan dos claves junto a `connecTO.lastMacName` y `connecTO.lastLinkMode`:

- `connecTO.lastHost`
- `connecTO.lastPort`

Si esas dos tienen valor y la fase es `.idle`, `reconnectIfNeeded` arma el `hostPort` y conecta. Una sesión abierta desde Bonjour borra `lastHost` y `lastPort`, y la reconexión vuelve a depender del nombre en la lista. `disconnect()` sigue dejando `suppressAuto` en true, así que salir a propósito no reabre la sesión.

Sigue siendo dato de la propia app (CA92.1 en `connecTO/PrivacyInfo.xcprivacy`). Cuando esto se publique, la frase de `docs/release.md` que cita el último Mac pasa a incluir host y puerto.

Prueba de cierre: lejos de casa, se mata la app y se vuelve a abrir. Entra al mismo Mac y al mismo modo sin escribir la dirección. Una sesión posterior por Bonjour, en casa, ya no intenta el host antiguo.

## El vídeo en ese camino

`ScreenCapturer.bitRate` pide entre 2 y 20 Mbps (5 Mbps a 1280×720). El lado largo por defecto es 1920 (`connecTO.longSide`). Una subida de casa de unos 10 Mbps aguanta el modo controlar a 30 fps. Monitor externo, a 2048×1536, se acerca al tope y se traba si la subida es justa.

Este plan no cambia el encoder. Si la imagen no da, se baja el lado largo con el ajuste de nitidez que ya existe.

## Lo que se queda para otro plan

Un relay propio, sin instalar Tailscale en el iPad. Los dos programas abrirían una salida TLS hacia un servidor, y ese servidor uniría las dos conexiones. Ahí sí hace falta una identidad más fuerte que el código de 6 dígitos, porque el servicio queda en internet. Este documento no lo diseña.
