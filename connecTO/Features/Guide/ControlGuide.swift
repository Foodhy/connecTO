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
            detail: "Un dedo mueve el cursor sobre la imagen del Mac. Dos dedos desplazan. Un toque no hace clic hasta que enciendas Clic."
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
            detail: "Cambia al escritorio de la izquierda."
        ),
        ControlLesson(
            id: "windows",
            symbol: "chevron.up",
            title: "Ventanas",
            detail: "Muestra todas las ventanas. Si Anterior, Ventanas o Siguiente no hacen nada, activa los atajos de Mission Control en el Mac."
        ),
        ControlLesson(
            id: "nextSpace",
            symbol: "chevron.right",
            title: "Siguiente",
            detail: "Cambia al escritorio de la derecha."
        ),
        ControlLesson(
            id: "quality",
            symbol: "sparkles.tv",
            title: "Nitidez",
            detail: "Elige el lado largo de la imagen, en píxeles. Más píxeles se ven mejor y usan más red."
        ),
        ControlLesson(
            id: "media",
            symbol: "playpause",
            title: "Volumen y reproducción",
            detail: "En la fila de abajo, de izquierda a derecha: bajar volumen, silencio, subir volumen, anterior, pausa y siguiente."
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
