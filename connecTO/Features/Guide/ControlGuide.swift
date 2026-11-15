import Foundation

nonisolated struct ControlLesson: Equatable, Identifiable, Sendable {
    var id: String
    var symbol: String
    var title: String
    var detail: String
}

nonisolated enum ControlGuide {
    static let lessons: [ControlLesson] = [
        ControlLesson(
            id: "picture",
            symbol: "display",
            title: "La pantalla",
            detail: "Un dedo mueve el cursor sobre la imagen del Mac. Dos dedos desplazan. Separa dos dedos para acercar y júntalos para alejar; muévelos a la vez para recorrer lo ampliado. En un Magic Mouse, desliza un dedo sobre la superficie para subir o bajar. Un toque no hace clic hasta que enciendas Clic."
        ),
        ControlLesson(
            id: "click",
            symbol: "cursorarrow.click",
            title: "Clic",
            detail: "Tócalo y se pone naranja. El siguiente toque en la imagen hace clic izquierdo. Tócalo otra vez para apagarlo."
        ),
        ControlLesson(
            id: "rightClick",
            symbol: "contextualmenu.and.cursorarrow",
            title: "Clic derecho",
            detail: "Hace clic derecho donde ya está el cursor. No hace falta tocar la imagen."
        ),
        ControlLesson(
            id: "drag",
            symbol: "hand.draw",
            title: "Arrastrar",
            detail: "Se pone naranja. Mantén el dedo en la imagen para arrastrar y levántalo para soltar. Clic y Arrastrar no están activos a la vez."
        ),
        ControlLesson(
            id: "keyboard",
            symbol: "keyboard",
            title: "Teclado",
            detail: "Abre una barra para escribir. Ahí están ⌘, ⌥, ⇧, ⌃, esc, tab, borrar, enter y las flechas."
        ),
        ControlLesson(
            id: "previousSpace",
            symbol: "chevron.left",
            title: "Anterior",
            detail: "Cambia al escritorio de la izquierda. Va con Control, así que un video no salta hacia atrás."
        ),
        ControlLesson(
            id: "windows",
            symbol: "chevron.up",
            title: "Ventanas",
            detail: "La primera vez es Control y flecha arriba: todos los escritorios y ventanas. Otra vez es Control y flecha abajo: las ventanas de la app. Si no cambia nada, activa los atajos de Mission Control en el Mac."
        ),
        ControlLesson(
            id: "nextSpace",
            symbol: "chevron.right",
            title: "Siguiente",
            detail: "Cambia al escritorio de la derecha. Va con Control, así que un video no salta hacia adelante."
        ),
        ControlLesson(
            id: "quality",
            symbol: "sparkles.tv",
            title: "Nitidez",
            detail: "Elige el lado largo de la imagen, en píxeles. Más píxeles se ven mejor y usan más red."
        ),
        ControlLesson(
            id: "display",
            symbol: "display",
            title: "Pantalla",
            detail: "Elige qué monitor del Mac se ve. El cursor cae en esa pantalla."
        ),
        ControlLesson(
            id: "extend",
            symbol: "rectangle.connected.to.line.below",
            title: "Monitor externo",
            detail: "Al elegir el Mac puedes controlar una pantalla que ya tiene, o ser un monitor más. En monitor la imagen ocupa todo el iPad. El número cambia la resolución. El botón rojo abre la pregunta para terminar la sesión."
        ),
        ControlLesson(
            id: "sound",
            symbol: "speaker.wave.2",
            title: "Sonido",
            detail: "En el Mac el audio se queda ahí. En el iPad lo escuchas en este aparato y el Mac se silencia hasta que lo devuelves."
        ),
        ControlLesson(
            id: "media",
            symbol: "playpause",
            title: "Volumen y reproducción",
            detail: "En la misma fila, solo el icono: bajar volumen, silencio, subir volumen, pista anterior, pausa y pista siguiente. Desconectar es el último, en rojo. Desliza la fila si no caben."
        ),
        ControlLesson(
            id: "permissions",
            symbol: "checkmark.shield",
            title: "Permisos del Mac",
            detail: "Accesibilidad mueve el cursor. Grabación de pantalla muestra el escritorio. Los dos se activan en el menú de connecTO, en la barra de menú del Mac."
        ),
        ControlLesson(
            id: "code",
            symbol: "number",
            title: "El código",
            detail: "La primera vez, abre el menú de connecTO en el Mac y escribe aquí los seis dígitos."
        ),
    ]
}
