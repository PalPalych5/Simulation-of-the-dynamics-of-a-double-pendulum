import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Popup {
    id: helpPopup
    x: 0
    y: 0
    width: parent.width
    height: parent.height
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 20

    background: Rectangle {
        color: mainWindow.isDarkTheme ? "#3A3A3A" : "#F5F5F5"
        border.color: mainWindow.isDarkTheme ? "#555555" : "#C0C0C0"
    }

    Button {
        id: closeIcon
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 5

        icon.source: "qrc:/icons/cross.svg"
        icon.width: 18
        icon.height: 18
        icon.color: mainWindow.isDarkTheme ? "#CCCCCC" : "#333333"

        flat: true
        background: Item {}
        onClicked: helpPopup.close()
        
        ToolTip.text: "Закрыть (Esc)"
        ToolTip.visible: hovered
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Label {
            text: qsTr("Руководство пользователя")
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 15
            Layout.bottomMargin: 10
            font.bold: true
            font.pixelSize: 22
            color: mainWindow.isDarkTheme ? "#E0E0E0" : "#222222"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.bottomMargin: 10
            color: mainWindow.isDarkTheme ? "#555" : "#CCC"
        }

        ScrollView {
            id: helpScrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Item {
                width: helpScrollView.availableWidth
                implicitHeight: helpText.implicitHeight
            
                Text {
                    id: helpText
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textFormat: Text.RichText
                    
                    onLinkActivated: function(link) {
                        Qt.openUrlExternally(link)
                    }

                    color: mainWindow.isDarkTheme ? "#DCDCDC" : "#333333"

                    text: {
                        var githubLink = "https://github.com/PalPalych5/Simulation-of-the-dynamics-of-a-double-pendulum";
                        var headerColor = mainWindow.isDarkTheme ? '#AADEFF' : '#005A9C';
                        var linkColor = mainWindow.isDarkTheme ? '#66B2FF' : '#0078D7';

                        return `
                        <p style="font-size:14px; line-height:1.5;">Добро пожаловать в симулятор двойного маятника! Эта программа представляет собой интерактивную виртуальную лабораторию для исследования сложной и увлекательной динамики двойного маятника — классической системы, демонстрирующей явление детерминированного хаоса.</p>
                        <hr>
                        <p style="font-size:18px; color:${headerColor};"><b>1. Основные элементы управления</b></p>
                        
                        <p style="font-size:16px;"><b>Панель инструментов (сверху)</b></p>
                        <ul style="font-size:14px;">
                            <li><b>Переключатель режимов:</b> Переключает интерфейс между режимами "Симуляция" и "Анализ".</li>
                            <li><b>Добавить график (+):</b> Появляется в режиме "Анализ" и создает новое окно для построения графика.</li>
                            <li><b>Настройки (⚙️):</b> Открывает диалог для настройки параметров 3D-графики и отображения FPS.</li>
                            <li><b>Справка (?):</b> Открывает это руководство.</li>
                            <li><b>Смена темы (солнце/луна):</b> Мгновенно переключает оформление между светлой и темной темами.</li>
                            <li><b>Слайдер скорости:</b> Управляет скоростью течения времени в симуляции.</li>
                            <li><b>Сброс (⟲):</b> Возвращает маятник в начальное состояние, заданное в полях ввода, и очищает всю историю.</li>
                            <li><b>Старт / Пауза:</b> Запускает или приостанавливает симуляцию.</li>
                            <li><b>Шаг вперед (→):</b> Появляется на паузе, позволяет продвинуть симуляцию на один микрошаг.</li>
                        </ul>

                        <p style="font-size:16px;"><b>Панель симуляции (справа)</b></p>
                        <ul style="font-size:14px;">
                            <li><b>2D-проекция:</b> Интерактивный холст, где можно <b>задавать начальные углы</b> перетаскиванием грузов мышью.</li>
                            <li><b>Управление 2D-видом:</b> Кнопки позволяют включать/выключать <b>следы</b>, отображать <b>координатные сетки</b> и <b>экспортировать</b> вид в PNG.</li>
                            <li><b>Панель телеметрии:</b> Отображает <i>текущие</i> значения параметров и энергий. Только для чтения.</li>
                            <li><b>Панель управления параметрами:</b> Здесь вы задаете <i>начальные</i> условия и константы. Все изменения применяются по кнопке "Сброс".</li>
                        </ul>
                        <hr>
                        
                        <p style="font-size:18px; color:${headerColor};"><b>2. Режим "Анализ": Работа с графиками</b></p>
                        <p style="font-size:14px;">Предназначен для глубокого анализа данных. 3D-сцена заменяется областью для построения графиков.</p>
                        
                        <p style="font-size:16px;"><b>Управление графиком</b></p>
                        <ul style="font-size:14px;">
                            <li><b>Добавление/удаление:</b> Кнопка <b>"+"</b> создает новое окно. Кнопка <b>"×"</b> на каждом графике удаляет его.</li>
                            <li><b>Типы графиков:</b> Вы можете строить <b>временные ряды</b> (зависимость от времени t), <b>фазовые портреты</b> (например, ω₁(θ₁)) и <b>карты Пуанкаре</b>.</li>
                            <li><b>Интерактивность:</b> Масштабируйте временные ряды колесом мыши, перемещайте — зажав левую кнопку. Кнопка с глазом (👁️) возвращает к последним данным.</li>
                        </ul>

                        <p style="font-size:16px;"><b>Карта Пуанкаре: Особые возможности</b></p>
                        <p style="font-size:14px;">Карта Пуанкаре — мощнейший инструмент для визуализации хаоса. Она показывает состояние системы (ω₂ от θ₂) каждый раз, когда маятник пересекает плоскость θ₁=0.</p>
                        <ul style="font-size:14px;">
                             <li><b>Сравнительный анализ:</b> Палитра цветов позволяет накладывать несколько симуляций (аттракторов) друг на друга. Запустите одну, смените цвет, измените параметры, сбросьте и запустите снова. Старые точки останутся на карте.</li>
                             <li><b>Размер точек и Очистка (🗑️):</b> Позволяют настроить вид и удалить все точки с карты.</li>
                        </ul>
                        <hr>

                        <p style="font-size:18px; color:${headerColor};"><b>Об авторе и обратная связь</b></p>
                        <p style="font-size:14px;"><b>Автор:</b> Кудрявцев Павел Павлович<br>
                           Email: <a href="mailto:pavlikkudryavtsev@gmail.com" style="color:${linkColor};">pavlikkudryavtsev@gmail.com</a></p>
                        <p style="font-size:14px;">Проект является открытым, исходный код доступен на GitHub:<br>
                           <a href="${githubLink}"><img src="qrc:/images/github_icon.png" width="32"></a></p>
                        `
                    }
                }
            }
        }
    }
} 