import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtCharts
import QtQuick3D
import QtQuick3D.Helpers
import "qrc:/models/" // Добавляем импорт для доступа к компоненту DoublePendulum
// Import ParameterStepper component
import "qrc:/"
import QtQuick.Dialogs
// Import our new component
import "."

// REFACTORING NOTE: Connections blocks for pendulumObj are duplicated in the file.
// There is a consolidated Connections block at the top of the file (around line 79)
// and duplicate blocks at lines 2320 and 2464. In a future refactoring,
// these should be consolidated into the single block at the top of the file.

Window {
    id: mainWindow
    width: 800
    height: 600
    visible: true
    visibility: Window.Maximized // Запуск в развернутом виде на весь экран
    title: "Double Pendulum Simulation"
    color: mainWindow.isDarkTheme ? "#333333" : "#FFFFFF" // Чисто белый фон для светлой темы
    
    property bool initialCameraSet: false // Флаг для однократной настройки камеры
    
    Behavior on color { ColorAnimation { duration: 400 } }
    
    // --- HELPER-ФУНКЦИИ ДЛЯ КАЧЕСТВА AA ---
    function qualityToIndex(quality) {
        switch (quality) {
            case SceneEnvironment.Medium: return 0;
            case SceneEnvironment.High: return 1;
            case SceneEnvironment.VeryHigh: return 2;
            default: return 1; // По умолчанию 'Высокое' (индекс 1)
        }
    }

    function indexToQuality(index) {
        switch (index) {
            case 0: return SceneEnvironment.Medium;
            case 1: return SceneEnvironment.High;
            case 2: return SceneEnvironment.VeryHigh;
            default: return SceneEnvironment.High; // По умолчанию 'Высокое'
        }
    }
    
    // --- ДОБАВЛЯЕМ ЭТОТ БЛОК ---
    Behavior on color { ColorAnimation { duration: 400 } }
    
    // Property to track current mode (simulation or analysis)
    property bool analysisModeActive: false // false = simulation mode, true = analysis mode
    property bool showBob2RelativeGrid: false // Property for showing relative grid for bob2
    property bool isDarkTheme: false // false - светлая тема, true - темная тема
    
    // Свойство для анимированного цвета фона 3D сцены
    property color sceneBackgroundColor: isDarkTheme ? "#404040" : "#F0F0F0"
    
    // При изменении этого свойства обновляем реальный фон сцены
    onSceneBackgroundColorChanged: {
        if (view3D && view3D.environment) {
            view3D.environment.clearColor = sceneBackgroundColor;
        }
    }
    
    // Анимация для плавного изменения цвета фона 3D сцены
    ColorAnimation {
        id: sceneColorAnimation
        target: mainWindow
        property: "sceneBackgroundColor"
        duration: 400
        easing.type: Easing.InOutQuad
    }
    
    // --- Свойства для хранения ссылок на узлы ---
    // Контроллеры для вращения
    property var link1Pivot: null
    property var link2Pivot: null

    // Меши для масштабирования
    property var rod1Mesh: null
    property var rod2Mesh: null
    property var bob1Mesh: null
    property var bob11Mesh: null
    property var bob2Mesh: null
    
    // Функция поиска узла по имени (рекурсивно)
    function findNodeByName(rootModel, nodeName) {
        if (!rootModel) return null;
        
        // Проверяем все дочерние узлы модели
        function searchInChildren(node) {
            if (!node) return null;
            
            // Проверяем имя текущего узла
            if (node.objectName === nodeName) {
                console.log("Found node:", nodeName);
                return node;
            }
            
            // Рекурсивно ищем в дочерних узлах
            var children = node.children || [];
            for (var i = 0; i < children.length; i++) {
                var result = searchInChildren(children[i]);
                if (result) return result;
            }
            
            return null;
        }
        
        return searchInChildren(rootModel);
    }
    
    function applyMaterialToPendulum(materialComponent) {
        if (!pendulum3DModel || !materialComponent) {
            console.error("Cannot apply material: pendulum3DModel or materialComponent is missing.");
            return;
        }

        // Список всех узлов типа Model, которым нужно сменить материал
        var modelNodeNames = ["base", "bob11", "bob1", "bob2", "rod2", "rod1", "top"];

        for (var i = 0; i < modelNodeNames.length; i++) {
            var node = findNodeByName(pendulum3DModel, modelNodeNames[i]);
            if (node) {
                // Свойство 'materials' ожидает массив. Создаем новый материал для каждого узла.
                node.materials = [materialComponent.createObject(node)];
            } else {
                console.warn("Could not find a model node:", modelNodeNames[i]);
            }
        }
    }
    
    // FPS settings
    property bool fpsCounterVisible: false // Whether to show FPS counter
    property bool limitFpsEnabled: false // Whether to limit FPS
    property int targetMaxFps: 60 // Target max FPS when limited

    // Using context property directly - the pendulum object comes from C++
    property var pendulumObj: pendulum // Direct reference to context property

    // Point of suspension for the pendulum
    property real suspensionPointX: width / 2
    property real suspensionPointY: height / 3
    
    // Rod lengths as constants
    property real rod1Length: 150
    property real rod2Length: 120
    
    // ВСТАВИТЬ НОВУЮ ФУНКЦИЮ ЗДЕСЬ
    function forceFullRedrawOfOffscreenTraces() {
        if (traceDrawer && pendulumObj) {
            traceDrawer.clearAllTraces();
            traceDrawer.updateAndDrawNewTraceSegments(true);
            if (pendulumCanvas && pendulumCanvas.available) {
                pendulumCanvas.requestPaint(); // Request repaint to display the updated traces
            }
        }
    }

    function formatAdaptive(value, digitsMostPrecise, digitsLeastPrecise) {
        if (value === undefined || value === null || isNaN(value)) {
            return "N/A"; 
        }
        var absValue = Math.abs(value);
        var numDigits;

        if (absValue < 10.0) { // Для чисел по модулю меньше 10 (например, 0.123, -5.678)
            numDigits = digitsMostPrecise; // Больше знаков
        } else if (absValue < 100.0) { // Для чисел по модулю от 10 до 99.9... (например, 12.34, -56.7)
            numDigits = Math.max(0, digitsMostPrecise - 1); // На один знак меньше
        } else { // Для чисел по модулю 100 и больше (например, 123.4, -567)
            numDigits = digitsLeastPrecise; // Еще меньше знаков
        }
        
        numDigits = Math.max(0, numDigits); // Гарантируем неотрицательное количество знаков
        return Number(value).toFixed(numDigits);
    }
    
    function isAnyPoincareChartActive() {
        if (!analysisModeActive || !chartsColumnLayout) {
            return false;
        }
        
        for (var i = 0; i < chartsColumnLayout.children.length; ++i) {
            var chart = chartsColumnLayout.children[i];
            if (chart && chart.visible && chart.currentChartType === "poincare") {
                return true;
            }
        }
        
        return false;
    }
    
    // --- FPS Counter ---
    property int frameCount: 0
    property real lastTime: 0
    property real fps: 0

    Timer {
        interval: 1000 // Обновляем FPS раз в секунду
        running: true
        repeat: true
        onTriggered: {
            var currentTime = Date.now();
            if (mainWindow.lastTime > 0) {
                var deltaTime = (currentTime - mainWindow.lastTime) / 1000.0;
                mainWindow.fps = mainWindow.frameCount / deltaTime;
            }
            mainWindow.lastTime = currentTime;
            mainWindow.frameCount = 0;
            // console.log("FPS:", mainWindow.fps.toFixed(1)); // Можно раскомментировать для вывода в консоль
        }
    }

    // Функция для сохранения всех активных серий точек Пуанкаре перед сбросом
    function finalizeAllPoincareSeriesBeforeReset() {
        if (mainWindow.analysisModeActive && chartsColumnLayout) {
            for (var i = 0; i < chartsColumnLayout.children.length; ++i) {
                var chartPlaceholder = chartsColumnLayout.children[i];
                if (chartPlaceholder && chartPlaceholder.currentChartType === "poincare") {
                    chartPlaceholder.finalizeCurrentPoincareSeries();
                }
            }
        }
    }

    // Main layout structure
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        
        // Top toolbar panel
        Rectangle {
            id: topToolbar
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: mainWindow.isDarkTheme ? "#424242" : "#E5E5E5"
            
            // --- ДОБАВЛЯЕМ ЭТОТ БЛОК ---
            Behavior on color { ColorAnimation { duration: 400 } }
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 3
                
                // Левая группа кнопок
                Button {
                    id: modeSwitchButton
                    text: ""
                    icon.source: mainWindow.analysisModeActive ? "qrc:/icons/3D.svg" : "qrc:/icons/analysis.svg"
                    icon.width: 26
                    icon.height: 26
                    icon.color: mainWindow.isDarkTheme ? "#CCCCCC" : "#333333"
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.text: mainWindow.analysisModeActive ? "Режим симуляции" : "Режим анализа"
                    ToolTip.visible: hovered
                    padding: 2
                    flat: true
                    background: Item {}
                    onClicked: {
                        mainWindow.analysisModeActive = !mainWindow.analysisModeActive;

                        if (mainWindow.analysisModeActive) {
                            if (simulationTimer.running) {
                                simulationTimer.stop();
                            }
                            // When switching to analysis mode, update all charts once immediately
                            if (chartsColumnLayout) {
                                for (var i = 0; i < chartsColumnLayout.children.length; ++i) {
                                    var chart = chartsColumnLayout.children[i];
                                    if (chart && chart.visible && typeof chart.updateChartDataAndPaint === "function") {
                                        chart.updateChartDataAndPaint();
                                    }
                                }
                            }
                            // The master timer's "running" property will handle starting/stopping automatically
                        } else {
                            // Stop master timer when exiting analysis mode
                            masterChartUpdateTimer.stop();
                        }
                    }
                }
                
                Button {
                    id: addChartButton
                    text: ""
                    icon.source: "qrc:/icons/plus.svg"
                    icon.width: 26
                    icon.height: 26
                    icon.color: mainWindow.isDarkTheme ? "#CCCCCC" : "#333333"
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    visible: mainWindow.analysisModeActive
                    ToolTip.text: "Добавить график"
                    ToolTip.visible: hovered
                    padding: 2
                    flat: true
                    background: Item {}
                    onClicked: {
                        var placeholder = chartsAreaContainer.createChartPlaceholder();
                        if (placeholder) {
                            // Placeholder was successfully created
                        }
                    }
                }
                
                Button {
                    id: settingsButton
                    icon.source: "qrc:/icons/settings.svg"
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    icon.width: 26
                    icon.height: 26
                    icon.color: mainWindow.isDarkTheme ? "#CCCCCC" : "#333333"
                    ToolTip.text: "Настройки"
                    ToolTip.visible: hovered
                    padding: 2
                    flat: true
                    background: Item {}
                    onClicked: settingsDialog.open()
                }
                
                Button {
                    id: helpButton
                    icon.source: "qrc:/icons/help.svg"
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    icon.width: 26
                    icon.height: 26
                    icon.color: mainWindow.isDarkTheme ? "#CCCCCC" : "#333333"
                    ToolTip.text: qsTr("Руководство пользователя")
                    ToolTip.visible: hovered
                    padding: 2
                    flat: true
                    background: Item {}
                    onClicked: helpPopup.open()
                }
                
                Button {
                    id: themeSwitchButton
                    icon.source: mainWindow.isDarkTheme ? "qrc:/icons/sun.svg" : "qrc:/icons/moon.svg"
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    icon.width: 26
                    icon.height: 26
                    icon.color: mainWindow.isDarkTheme ? "#CCCCCC" : "#333333"
                    ToolTip.text: mainWindow.isDarkTheme ? "Светлая тема" : "Темная тема"
                    ToolTip.visible: hovered
                    padding: 2
                    flat: true
                    background: Item {}
                    onClicked: {
                        mainWindow.isDarkTheme = !mainWindow.isDarkTheme;
                        console.log("Theme switched by button. mainWindow.isDarkTheme:", mainWindow.isDarkTheme);
                        
                        // Запускаем анимацию для фона 3D сцены
                        sceneColorAnimation.to = mainWindow.isDarkTheme ? "#404040" : "#F0F0F0";
                        sceneColorAnimation.start();
                        
                        // Обновить тему для существующих графиков
                        if (chartsColumnLayout) {
                            for (var i = 0; i < chartsColumnLayout.children.length; ++i) {
                                var chart = chartsColumnLayout.children[i];
                                if (chart && chart.hasOwnProperty('isDarkTheme')) {
                                    // Просто устанавливаем свойство, ChartPlaceholder сам среагирует
                                    chart.isDarkTheme = mainWindow.isDarkTheme;
                                }
                            }
                        }
                    }
                }
                
                // Simulation time display
                RowLayout {
                    id: timeSectionContainer // Новый контейнер для иконки и текста времени
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 3 // Отступ между иконкой и текстом
                    Layout.leftMargin: 10
                    Layout.rightMargin: 20 // << CHANGED FROM 10 to 20

                    Button { // Используем Button для иконки, чтобы работало icon.color
                        id: clockIconDisplay // Это не интерактивная кнопка, а просто дисплей иконки
                        icon.source: "qrc:/icons/clock.svg" // Убедитесь, что файл есть в ресурсах
                        
                        Layout.preferredWidth: 22  // Подберите размер, чтобы соответствовать другим иконкам
                        Layout.preferredHeight: 22 // или немного меньше, если нужно
                        icon.width: 16             // Размер самой картинки иконки
                        icon.height: 16
                        
                        padding: 0                 // Убираем внутренние отступы кнопки
                        flat: true                 // Убираем стандартный вид кнопки
                        background: Item {}        // Полностью прозрачный фон, чтобы была видна только иконка
                        
                        icon.color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333" // Цвет иконки для темы

                        enabled: false             // Делаем некликабельной
                        focusPolicy: Qt.NoFocus    // Убираем возможность фокуса
                    }

                    Text {
                        id: timeValueText // Новое id для текста только со значением времени
                        text: (pendulumObj ? pendulumObj.currentTime.toFixed(2) : "0.00") + " с"
                        color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333" // Цвет текста для темы
                        Layout.alignment: Qt.AlignVCenter
                        font.pixelSize: 16 // Увеличено с 14 до 16
                        font.bold: false 
                    }
                }
                
                // FPS display - REMOVED (moved to speedControlButtonsLayout)
                
                RowLayout {
                        id: speedControlButtonsLayout
                        Layout.alignment: Qt.AlignVCenter
                        Layout.maximumWidth: implicitWidth
                        spacing: 10

                        property var speedValues: [0.1, 0.2, 0.5, 0.8, 1.0, 1.5, 2.0, 3.0, 5.0, 8.0, 10.0, 15.0, 20.0, 25.0, 35.0, 50.0]

                        Slider {
                            id: speedSlider
                            Layout.fillWidth: true
                            Layout.preferredWidth: 200
                            Layout.alignment: Qt.AlignVCenter
                            
                            from: 0
                            to: speedControlButtonsLayout.speedValues.length - 1
                            stepSize: 1
                            snapMode: Slider.SnapAlways
                            
                            value: { // Привязка значения слайдера к скорости маятника
                                if (pendulumObj) {
                                    var index = speedControlButtonsLayout.speedValues.indexOf(pendulumObj.simulationSpeed);
                                    return index !== -1 ? index : speedControlButtonsLayout.speedValues.indexOf(1.0); // По умолчанию на 1.0x
                                }
                                return speedControlButtonsLayout.speedValues.indexOf(1.0);
                            }

                            onValueChanged: { // Используем onValueChanged, так как snapMode активен
                                if (pendulumObj) {
                                    var newSpeed = speedControlButtonsLayout.speedValues[value];
                                    if (pendulumObj.simulationSpeed !== newSpeed) {
                                        pendulumObj.simulationSpeed = newSpeed;
                                    }
                                }
                            }

                            background: Rectangle {
                                x: speedSlider.leftPadding
                                y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                                implicitWidth: 200
                                implicitHeight: 10
                                width: speedSlider.availableWidth
                                height: implicitHeight
                                radius: 4
                                color: mainWindow.isDarkTheme ? "#606060" : "#D0D0D0"
                                border.color: mainWindow.isDarkTheme ? "#808080" : "#B0B0B0"
                                border.width: 1
                            }

                            handle: Rectangle {
                                x: speedSlider.leftPadding + speedSlider.visualPosition * speedSlider.availableWidth - width / 2
                                y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                                implicitWidth: 40
                                implicitHeight: 24
                                radius: 6
                                color: mainWindow.isDarkTheme ? "#CCCCCC" : "#555555"
                                border.color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: {
                                        var currentIndex = speedSlider.value;
                                        var speeds = speedControlButtonsLayout.speedValues;
                                        if (currentIndex === speeds.length - 1) { // If it's the last element (maximum speed)
                                            return "Max";
                                        } else {
                                            return speeds[currentIndex].toLocaleString(Qt.locale(), 'f', 1);
                                        }
                                    }
                                    color: mainWindow.isDarkTheme ? "#222222" : "#FFFFFF"
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }
                        }
                        
                        // Moved FPS display
                        Text {
                            id: fpsText
                            text: "FPS: " + mainWindow.fps.toFixed(1)
                            Layout.alignment: Qt.AlignVCenter
                            font.pixelSize: 14
                            Layout.leftMargin: 15
                            color: mainWindow.isDarkTheme ? "white" : "black"
                            visible: mainWindow.fpsCounterVisible
                        }
                    }
                
                Item { Layout.fillWidth: true } // Spacer
                
                // Control panel (moved from bottom panel)
                Rectangle {
                    id: controlPanel
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: controlPanelLayout.implicitWidth
                    Layout.preferredHeight: controlPanelLayout.implicitHeight
                    color: "transparent"
                    
                    RowLayout {
                        id: controlPanelLayout
                        x: 0
                        y: 0 
                        spacing: 5
                        Layout.alignment: Qt.AlignVCenter
                        // Add this to prevent visual glitches during animation
                        clip: true
                        
                        Button {
                            id: resetButton
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Layout.alignment: Qt.AlignVCenter
                            flat: true
                            icon.source: "qrc:/icons/reset.svg"
                            icon.width: 26
                            icon.height: 26
                            icon.color: mainWindow.isDarkTheme ? "#CCCCCC" : "#333333"
                            padding: 2
                            background: Item {}
                            onClicked: {
                                // Завершаем текущие серии Пуанкаре перед сбросом
                                finalizeAllPoincareSeriesBeforeReset();
                                
                                // Сбрасываем маятник с текущими значениями из SpinBox'ов
                                mainWindow.resetPendulumWithCurrentValues();
                                
                                // Очищаем визуальные следы с помощью трассировщика
                                if (pendulumCanvas) {
                                    pendulumCanvas.clearTraces();
                                }
                                
                                // Запрашиваем перерисовку канваса для отображения начального положения маятника
                                if (pendulumCanvas && pendulumCanvas.available) {
                                    pendulumCanvas.requestPaint();
                                }
                            }
                        }
                        
                        Button {
                            id: startStopButton
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Layout.alignment: Qt.AlignVCenter
                            flat: true
                            icon.source: simulationTimer.running ? "qrc:/icons/pause.svg" : "qrc:/icons/play.svg"
                            icon.width: 26
                            icon.height: 26
                            icon.color: mainWindow.isDarkTheme ? "#CCCCCC" : "#333333"
                            padding: 2
                            background: Item {}
                            onClicked: simulationTimer.running = !simulationTimer.running
                        }
                        
                        Button {
                            id: stepForwardButton
                            Layout.preferredWidth: 40 // Fixed initial width, will be animated
                            Layout.preferredHeight: 40
                            Layout.alignment: Qt.AlignVCenter
                            flat: true
                            
                            icon.source: "qrc:/icons/step.svg"
                            icon.width: 26
                            icon.height: 26
                            icon.color: mainWindow.isDarkTheme ? "#CCCCCC" : "#333333"
                            
                            padding: 2
                            background: Item {}
                            
                            // 1. УБРАЛИ 'visible'. Видимость контролируется ТОЛЬКО прозрачностью.
                            opacity: simulationTimer.running ? 0.0 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            
                            // 2. Отключаем кнопку, когда она невидима, чтобы избежать случайных нажатий.
                            enabled: !simulationTimer.running
                            
                            // 3. Анимация ширины, запускаемая с задержкой, чтобы макет сдвигался плавно.
                            SequentialAnimation {
                                id: widthAnimation
                                
                                PauseAnimation { duration: 50 } // Задержка перед началом сжатия/расширения
                                
                                NumberAnimation {
                                    target: stepForwardButton
                                    property: "Layout.preferredWidth"
                                    duration: 300
                                    easing.type: Easing.InOutQuad
                                }
                            }
                            
                            // 4. Триггер, который запускает анимацию ширины при смене состояния.
                            Connections {
                                target: simulationTimer
                                function onRunningChanged() {
                                    var targetWidth = simulationTimer.running ? 0 : 40;
                                    widthAnimation.animations[1].to = targetWidth; // Устанавливаем целевую ширину
                                    widthAnimation.start(); // Запускаем последовательность (пауза -> анимация)
                                }
                            }
                            
                            onClicked: {
                                if (mainWindow.pendulumObj) {
                                    // Call C++ step() method directly, simulating one frame (16 ms ~ 60 FPS)
                                    mainWindow.pendulumObj.step(16 / 1000.0);
                                    
                                    // Also increment frame count so FPS counter (if enabled) will react
                                    mainWindow.frameCount++;
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Center area with left and right panels
        RowLayout {
            id: mainHorizontalLayout
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            
            // Left panel container (for both 3D and charts)
            Item {
                id: leftPanelContainer
                Layout.preferredWidth: Math.round(mainWindow.width * 0.65)
                Layout.fillHeight: true
                Layout.minimumHeight: 400 // ПРИНУДИТЕЛЬНАЯ МИНИМАЛЬНАЯ ВЫСОТА ДЛЯ ТЕСТА
                clip: true
                
                // Left panel for 3D visualization (visible in simulation mode)
                Component {
                    id: polishedAluminumMaterial
                    PrincipledMaterial {
                        // ИЗМЕНЕНО: Чуть светлее для более чистого металлического блеска
                        baseColor: "#4A4A4A" 
                        metalness: 1.0
                        roughness: 0.2
                        cullMode: PrincipledMaterial.NoCulling
                        alphaMode: PrincipledMaterial.Opaque
                    }
                }

                Component {
                    id: matteGrayMaterial
                    PrincipledMaterial {
                        // ИЗМЕНЕНО: Чуть темнее для более насыщенного матового вида
                        baseColor: "#2c2c2c" 
                        metalness: 0.0
                        roughness: 0.7
                        cullMode: PrincipledMaterial.NoCulling
                        alphaMode: PrincipledMaterial.Opaque
                    }
                }

                View3D {
                    id: view3D
                    anchors.fill: parent
                    opacity: mainWindow.analysisModeActive ? 0.0 : 1.0
                    enabled: !mainWindow.analysisModeActive

                    // 2. Сбалансированное окружение для нейтрального рендеринга
                    environment: SceneEnvironment {
                        // Цвет фона теперь привязан к анимируемому свойству
                        clearColor: mainWindow.sceneBackgroundColor
                        backgroundMode: SceneEnvironment.Color

                        // HDR-карта остается для создания реалистичных отражений,
                        // но теперь материал правильно с ними взаимодействует.
                        lightProbe: Texture {
                            source: "qrc:/images/studio_env.hdr"
                        }

                        // Включаем качественное сглаживание и затенение
                        antialiasingMode: SceneEnvironment.MSAA
                        antialiasingQuality: SceneEnvironment.High  // Соответствует индексу 1 в новой схеме
                        aoEnabled: true
                        aoStrength: 0.8
                        aoDistance: 25.0
                        aoSoftness: 0.5
                    }

                    Behavior on opacity { NumberAnimation { duration: 300 } }

                    // --- ИСТОЧНИКИ СВЕТА С МЯГКИМИ ТЕНЯМИ ---
                    Node {
                        id: cameraPivot
                        
                        PerspectiveCamera {
                            id: camera
                            position: Qt.vector3d(0, 0, 5)
                            clipNear: 0.1
                            clipFar: 1000.0
                        }

                        DirectionalLight { 
                            eulerRotation.x: -45
                            eulerRotation.y: 35
                            brightness: 2.2
                            castsShadow: true
                            color: "white"
                            shadowMapQuality: Light.ShadowMapQualityVeryHigh
                            shadowFactor: 0.7 
                        }
                        
                        DirectionalLight { 
                            eulerRotation.x: 30
                            eulerRotation.y: -50
                            brightness: 0.9
                            color: "white"
                        }
                    }
                    
                    OrbitCameraController { camera: camera; origin: cameraPivot }

                    // МОДЕЛЬ
                    DoublePendulum {
                        id: pendulum3DModel
                        scale: Qt.vector3d(0.01, 0.01, 0.01)
                        position: Qt.vector3d(0, 0, 0)
                    }
                }
                
                // Consolidated Connections to pendulumObj for all signal handlers
                Connections {
                    target: pendulumObj
                    
                    // From the original block at line 2321 - updating controls
                    function onM1Changed() {
                        if (m1Input && pendulumObj) {
                            var realValueFromCpp = pendulumObj.m1;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * m1Input.decimalFactor);
                            if (m1Input.value !== spinBoxShouldDisplayInternalValue) {
                                m1Input.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    function onM2Changed() {
                        if (m2Input && pendulumObj) {
                            var realValueFromCpp = pendulumObj.m2;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * m2Input.decimalFactor);
                            if (m2Input.value !== spinBoxShouldDisplayInternalValue) {
                                m2Input.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    function onM1_rodChanged() {
                        if (m1RodInput && pendulumObj) {
                            var realValueFromCpp = pendulumObj.m1_rod;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * m1RodInput.decimalFactor);
                            if (m1RodInput.value !== spinBoxShouldDisplayInternalValue) {
                                m1RodInput.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    function onM2_rodChanged() {
                        if (m2RodInput && pendulumObj) {
                            var realValueFromCpp = pendulumObj.m2_rod;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * m2RodInput.decimalFactor);
                            if (m2RodInput.value !== spinBoxShouldDisplayInternalValue) {
                                m2RodInput.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    function onL1Changed() {
                        if (l1Input && pendulumObj) {
                            var realValueFromCpp = pendulumObj.l1;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * l1Input.decimalFactor);
                            if (l1Input.value !== spinBoxShouldDisplayInternalValue) {
                                l1Input.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    function onL2Changed() {
                        if (l2Input && pendulumObj) {
                            var realValueFromCpp = pendulumObj.l2;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * l2Input.decimalFactor);
                            if (l2Input.value !== spinBoxShouldDisplayInternalValue) {
                                l2Input.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    function onB1Changed() {
                        if (b1Input && pendulumObj) {
                            var realValueFromCpp = pendulumObj.b1;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * b1Input.decimalFactor);
                            if (b1Input.value !== spinBoxShouldDisplayInternalValue) {
                                b1Input.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    function onB2Changed() {
                        if (b2Input && pendulumObj) {
                            var realValueFromCpp = pendulumObj.b2;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * b2Input.decimalFactor);
                            if (b2Input.value !== spinBoxShouldDisplayInternalValue) {
                                b2Input.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    function onC1Changed() {
                        if (c1Input && pendulumObj) {
                            var realValueFromCpp = pendulumObj.c1;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * c1Input.decimalFactor);
                            if (c1Input.value !== spinBoxShouldDisplayInternalValue) {
                                c1Input.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    function onC2Changed() {
                        if (c2Input && pendulumObj) {
                            var realValueFromCpp = pendulumObj.c2;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * c2Input.decimalFactor);
                            if (c2Input.value !== spinBoxShouldDisplayInternalValue) {
                                c2Input.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    function onGChanged() {
                        if (gInput && pendulumObj) {
                            var realValueFromCpp = pendulumObj.g;
                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * gInput.decimalFactor);
                            if (gInput.value !== spinBoxShouldDisplayInternalValue) {
                                gInput.value = spinBoxShouldDisplayInternalValue;
                            }
                        }
                    }
                    
                    // From the original block at line 2464 - simulation failure handling
                    function onSimulationFailedChanged() {
                        if (pendulumObj.simulationFailed) {
                            simulationTimer.stop();
                            startStopButton.text = "Start";
                        }
                    }
                    
                    // From the original block at line 764 - 3D model update
                    function onStateChanged() {
                        // This code guarantees finding nodes on first call
                        if (!mainWindow.link1Pivot) {
                            mainWindow.link1Pivot = findNodeByName(pendulum3DModel, "Link1_Pivot");
                        }

                        // Update model rotation as before
                        if (mainWindow.link1Pivot) {
                            var angle1_deg = pendulumObj.theta1 * 180 / Math.PI;
                            var angle2_deg = pendulumObj.theta2 * 180 / Math.PI;
                            
                            // We need the second node only for rotation, find it here
                            if (!mainWindow.link2Pivot) {
                                 mainWindow.link2Pivot = findNodeByName(pendulum3DModel, "Link2_Pivot");
                            }
                            if (mainWindow.link2Pivot) {
                                mainWindow.link2Pivot.eulerRotation.y = -angle2_deg;
                            }
                            
                            mainWindow.link1Pivot.eulerRotation.y = -angle1_deg;

                            // IF camera is not yet configured, set it up ONCE
                            // on the already rotated model.
                            if (!mainWindow.initialCameraSet) {
                                var pivotGlobalPosition = pendulum3DModel.mapPositionToScene(mainWindow.link1Pivot.position);
                                cameraPivot.position = pivotGlobalPosition;
                                
                                // RESTORE ORIGINAL VALUES
                                cameraPivot.eulerRotation.x = 90;  // Tilt "down"
                                cameraPivot.eulerRotation.y = 180; // Rotate "sideways"
                                
                                mainWindow.initialCameraSet = true;
                            }
                        }
                    }
                }
                
                // Charts area (visible in analysis mode)
                Item {
                    id: chartsAreaContainer
                    anchors.fill: parent
                    opacity: mainWindow.analysisModeActive ? 1.0 : 0.0
                    enabled: mainWindow.analysisModeActive
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 300; easing.type: Easing.InOutQuad }
                    }
                    
                    // Replace the Behavior with a proper SequentialAnimation
                    SequentialAnimation {
                        id: chartWidthAnimation
                        running: false
                        
                        PauseAnimation { 
                            duration: 50 
                        }
                        
                        NumberAnimation {
                            target: chartsAreaContainer
                            property: "Layout.preferredWidth"
                            duration: 300
                            easing.type: Easing.InOutQuad
                        }
                    }
                    
                    Connections {
                        target: mainWindow
                        function onAnalysisModeActiveChanged() {
                            chartWidthAnimation.animations[1].to = mainWindow.analysisModeActive ? 
                                Math.round(mainWindow.width * 0.65) : 0;
                            chartWidthAnimation.start();
                        }
                    }
                    
                    clip: true

                    // Function to create chart placeholders dynamically
                    function createChartPlaceholder(titleText) {
                        if (titleText === undefined || titleText === null) {
                            console.warn("createChartPlaceholder called with undefined/null titleText. Using default.");
                            titleText = "График"; 
                        }
                        var component = Qt.createComponent("ChartPlaceholder.qml");
                        if (component.status === Component.Ready) {
                            var placeholder = component.createObject(chartsColumnLayout); // Сначала создаем объект
                            if (placeholder) {
                                // Затем устанавливаем свойства
                                placeholder.chartTitle = titleText; 
                                placeholder.pendulum = pendulumObj; 
                                placeholder.isDarkTheme = mainWindow.isDarkTheme; // Передаем тему
                                // No need to set visibility - the container's opacity handling takes care of it
                                
                                if (mainWindow.analysisModeActive) {
                                    // ИЗМЕНЕНИЕ: Оборачиваем вызов в Qt.callLater для отложенной инициализации
                                    Qt.callLater(function() {
                                        placeholder.updateChartDataAndPaint();
                                    });
                                }
                            } else {
                                console.error("Failed to create ChartPlaceholder instance.");
                            }
                            return placeholder;
                        } else {
                            console.error("Error creating chart placeholder component:", component.errorString());
                            return null;
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 5

                        ScrollView {
                            id: chartsScrollView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ColumnLayout {
                                id: chartsColumnLayout
                                width: chartsScrollView.availableWidth
                                Layout.fillHeight: true
                                spacing: 0  // Changed from 10 to 0 to avoid spacing between charts
                            }
                        }
                    }
                    
                    // Add initial chart placeholder when component is loaded
                    Component.onCompleted: {
                        chartsAreaContainer.createChartPlaceholder("График 1");
                    }
                }
            }
            
            // Right panel
            Rectangle {
                id: rightPanel
                Layout.preferredWidth: Math.round(mainWindow.width * 0.35)
                Layout.fillHeight: true
                color: mainWindow.isDarkTheme ? "#3E3E3E" : "#F8F8F8" // Светлее для светлой темы
                
                // --- ДОБАВЛЯЕМ ЭТОТ БЛОК ---
                Behavior on color { ColorAnimation { duration: 400 } }
                
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    
                    // Upper part of right panel (for 2D Canvas)
                    Rectangle {
                        id: canvasContainer
                        Layout.fillWidth: true
                        Layout.preferredHeight: canvasContainer.width
                        Layout.minimumHeight: 200 // Ensure there's always a minimum height
                        color: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF" // Чисто белый для светлой темы

                        // --- ДОБАВЛЯЕМ ЭТОТ БЛОК ---
                        Behavior on color { ColorAnimation { duration: 400 } }

                        GridLayout {
                            id: traceCheckBoxesLayout
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 5
                            columns: 2
                            rows: 2
                            columnSpacing: 5
                            rowSpacing: 5
                            z: 10 // Ensure buttons appear above the canvas

                            ToolButton {
                                id: traceBob1Button
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                icon.source: "qrc:/icons/scribble.svg"
                                icon.width: 18
                                icon.height: 18
                                icon.color: "red"
                                checkable: true
                                checked: pendulumObj ? pendulumObj.showTrace1 : false
                                ToolTip.text: "Траектория первого груза"
                                ToolTip.visible: hovered
                                
                                Binding {
                                    target: pendulumObj
                                    property: "showTrace1"
                                    value: traceBob1Button.checked
                                    when: pendulumObj
                                }
                                
                                onCheckedChanged: {
                                    console.log("traceBob1Button checked changed to: " + checked);
                                    if (pendulumObj) { 
                                        pendulumObj.showTrace1 = checked;
                                    }
                                    if (pendulumCanvas.available) {
                                        pendulumCanvas.requestPaint(); // Просто просим перерисоваться
                                    }
                                }
                                
                                background: Rectangle {
                                    color: traceBob1Button.checked ? (mainWindow.isDarkTheme ? "#555555" : "#C0C0C0") : "transparent"
                                    border.color: traceBob1Button.checked ? "#696969" : "gray"
                                    border.width: 1
                                    radius: 3
                                }
                                
                                opacity: checked ? 1.0 : 0.5
                            }
                            
                            ToolButton {
                                id: show2DGridButton
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                icon.source: "qrc:/icons/coordinate.svg"
                                icon.width: 18
                                icon.height: 18
                                icon.color: "red"
                                checkable: true
                                checked: mainWindow.show2DGridAndAxes
                                padding: 0
                                leftPadding: 0
                                rightPadding: 0
                                topPadding: 0
                                bottomPadding: 0
                                ToolTip.text: "Координатная сетка для первого груза"
                                ToolTip.visible: hovered
                                
                                onCheckedChanged: {
                                    mainWindow.show2DGridAndAxes = checked;
                                    if (pendulumCanvas.available) {
                                        pendulumCanvas.requestPaint();
                                    }
                                }
                                
                                background: Rectangle {
                                    color: show2DGridButton.checked ? (mainWindow.isDarkTheme ? "#555555" : "#C0C0C0") : "transparent"
                                    border.color: show2DGridButton.checked ? "#696969" : "gray"
                                    border.width: 1
                                    radius: 3
                                }
                                
                                opacity: checked ? 1.0 : 0.5
                            }
                            
                            ToolButton {
                                id: traceBob2Button
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                icon.source: "qrc:/icons/scribble.svg"
                                icon.width: 18
                                icon.height: 18
                                icon.color: "blue"
                                checkable: true
                                checked: pendulumObj ? pendulumObj.showTrace2 : false
                                ToolTip.text: "Траектория второго груза"
                                ToolTip.visible: hovered
                                
                                Binding {
                                    target: pendulumObj
                                    property: "showTrace2"
                                    value: traceBob2Button.checked
                                    when: pendulumObj
                                }
                                
                                onCheckedChanged: {
                                    console.log("traceBob2Button checked changed to: " + checked);
                                    if (pendulumObj) {
                                        pendulumObj.showTrace2 = checked;
                                    }
                                    if (pendulumCanvas.available) {
                                        pendulumCanvas.requestPaint(); // Просто просим перерисоваться
                                    }
                                }
                                
                                background: Rectangle {
                                    color: traceBob2Button.checked ? (mainWindow.isDarkTheme ? "#555555" : "#C0C0C0") : "transparent"
                                    border.color: traceBob2Button.checked ? "#696969" : "gray"
                                    border.width: 1
                                    radius: 3
                                }
                                
                                opacity: checked ? 1.0 : 0.5
                            }

                            ToolButton {
                                id: showBob2RelativeGridButton
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                icon.source: "qrc:/icons/coordinate.svg"
                                icon.width: 18
                                icon.height: 18
                                icon.color: "blue"
                                checkable: true
                                checked: mainWindow.showBob2RelativeGrid
                                padding: 0
                                leftPadding: 0
                                rightPadding: 0
                                topPadding: 0
                                bottomPadding: 0
                                ToolTip.text: "Локальная система координат для второго груза"
                                ToolTip.visible: hovered
                                
                                onCheckedChanged: {
                                    mainWindow.showBob2RelativeGrid = checked;
                                    if (pendulumCanvas.available) {
                                        pendulumCanvas.requestPaint();
                                    }
                                }
                                
                                background: Rectangle {
                                    color: showBob2RelativeGridButton.checked ? (mainWindow.isDarkTheme ? "#555555" : "#C0C0C0") : "transparent"
                                    border.color: showBob2RelativeGridButton.checked ? "#696969" : "gray"
                                    border.width: 1
                                    radius: 3
                                }
                                
                                opacity: checked ? 1.0 : 0.5
                            }
                        }

                        // Export trace button
                        Button {
                            id: exportTraceButton
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 10
                            z: traceCheckBoxesLayout.z + 1 // Ensure it's above other elements
                            
                            icon.source: "qrc:/icons/download.svg"
                            icon.width: 22
                            icon.height: 22
                            icon.color: mainWindow.isDarkTheme ? "#CCCCCC" : "#333333"
                            width: 32 // Fixed size
                            height: 32
                            ToolTip.text: "Экспорт 2D траекторий в PNG"
                            ToolTip.visible: hovered
                            padding: 1 // Reduced padding for more compact look
                            flat: true
                            background: Item {} // Remove standard button background
                            
                            onClicked: traceSaveDialog.open()
                        }

                        PendulumCanvas2D {
                            id: pendulumCanvas
                            anchors.fill: parent
                            pendulumObj: mainWindow.pendulumObj
                            isDarkTheme: mainWindow.isDarkTheme
                            showGrid: mainWindow.show2DGridAndAxes
                            showBob2RelativeGrid: mainWindow.showBob2RelativeGrid
                            poincareFlashEnabled: mainWindow.isAnyPoincareChartActive()
                        }

                        // Error overlay
                        Rectangle {
                            id: errorOverlay
                            anchors.fill: parent
                            color: mainWindow.isDarkTheme ? "#CC000000" : "#AA000000" // Semi-transparent dark color, darker for dark theme
                            visible: pendulumObj ? pendulumObj.simulationFailed : false

                            Text {
                                anchors.centerIn: parent
                                width: parent.width * 0.9
                                color: "white"
                                font.pixelSize: 14
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                text: "Симуляция нестабильна!\n\nПожалуйста, измените параметры или сбросьте симуляцию.\n(Попробуйте уменьшить скорость, коэффициенты трения/сопротивления или массы стержней до нуля)."
                            }
                        }
                    }
                    
                    // Lower part of right panel (for controls)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: mainWindow.isDarkTheme ? "#333333" : "#F5F5F5" // Changed from #ADB5BD to #F5F5F5 for a cleaner white appearance
                        
                        // --- ДОБАВЛЯЕМ ЭТОТ БЛОК ---
                        Behavior on color { ColorAnimation { duration: 400 } }
                        
                        ScrollView {
                            id: paramsScrollView
                            anchors.fill: parent
                            anchors.margins: 10
                            clip: true
                            
                            background: Rectangle {
                                color: mainWindow.isDarkTheme ? "#3E3E3E" : "#E8E8E8" // Цвет для светлой темы изменен на #E8E8E8
                                
                                // --- ДОБАВЛЯЕМ ЭТОТ БЛОК ---
                                Behavior on color { ColorAnimation { duration: 400 } }
                            }
                            
                            ColumnLayout {
                                width: paramsScrollView.availableWidth // Changed from paramsScrollView.width - 20
                                spacing: 10
                                // Layout.bottomMargin: 25 // Removed as per new instruction
                                
                                // Three-column parameter display layout
                                RowLayout {
                                    id: threeColumnDisplayLayout
                                    Layout.fillWidth: false // Ensure this is false or absent
                                    Layout.margins: 10
                                    spacing: 50 // Adjusted from 60
                                    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

                                    // Колонка 1: Параметры первого звена
                                    ColumnLayout {
                                        id: firstPendulumParamsColumn
                                        // Layout.preferredWidth: 180 // REMOVED
                                        Layout.fillWidth: false // Ensure this is false or absent
                                        spacing: 3
                                        Layout.alignment: Qt.AlignLeft | Qt.AlignTop

                                        GridLayout {
                                            columns: 2
                                            columnSpacing: 6
                                            rowSpacing: 3
                                            Layout.alignment: Qt.AlignLeft | Qt.AlignTop // Ensured
                                            // No Layout.fillWidth: true for the GridLayout itself

                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "m<sub>1</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.m1, 3, 1) + " кг"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "M<sub>1</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.m1_rod, 3, 1) + " кг"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "l<sub>1</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.l1, 3, 1) + " м"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "b<sub>1</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.b1, 3, 2); 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter;
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "c<sub>1</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.c1, 4, 2); 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "θ<sub>1</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.theta1, 3, 1) + " рад"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "θ<sub>1</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.theta1 * 180 / Math.PI, 1, 0) + "°"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "ω<sub>1</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.omega1, 3, 1) + " рад/с"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                        }
                                    }

                                    // Колонка 2: Общие параметры и Энергии
                                    ColumnLayout {
                                        id: commonAndEnergyParamsColumn
                                        // Layout.preferredWidth: 180 // REMOVED
                                        Layout.fillWidth: false // Ensure this is false or absent
                                        spacing: 3
                                        Layout.alignment: Qt.AlignLeft | Qt.AlignTop

                                        GridLayout {
                                            columns: 2
                                            columnSpacing: 6
                                            rowSpacing: 3
                                            Layout.alignment: Qt.AlignLeft | Qt.AlignTop // Ensured
                                            // No Layout.fillWidth: true for the GridLayout itself

                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "g ="; color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: formatAdaptive(pendulumObj.g, 2, 1) + " м/с<sup>2</sup>"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                        
                                            Text { 
                                                text: "T ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.currentKineticEnergy, 3, 1) + " Дж"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter;
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                text: "V ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.currentPotentialEnergy, 3, 1) + " Дж"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter;
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                text: "E ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.currentTotalEnergy, 3, 1) + " Дж"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                        }
                                    }

                                    // Колонка 3: Параметры второго звена
                                    ColumnLayout {
                                        id: secondPendulumParamsColumn
                                        // Layout.preferredWidth: 180 // REMOVED
                                        Layout.fillWidth: false // Ensure this is false or absent
                                        spacing: 3
                                        Layout.alignment: Qt.AlignLeft | Qt.AlignTop

                                        GridLayout {
                                            columns: 2
                                            columnSpacing: 6
                                            rowSpacing: 3
                                            Layout.alignment: Qt.AlignLeft | Qt.AlignTop // Ensured
                                            // No Layout.fillWidth: true for the GridLayout itself

                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "m<sub>2</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.m2, 3, 1) + " кг"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "M<sub>2</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.m2_rod, 3, 1) + " кг"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "l<sub>2</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.l2, 3, 1) + " м"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "b<sub>2</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.b2, 3, 2); 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "c<sub>2</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.c2, 4, 2); 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "θ<sub>2</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: mainWindow.formatAdaptive(pendulumObj.theta2, 3, 1) + " рад"
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "θ<sub>2</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: mainWindow.formatAdaptive(pendulumObj.theta2 * 180 / Math.PI + pendulumObj.theta1 * 180 / Math.PI , 1, 0) + "°"
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333";
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight 
                                            }
                                            
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "ω<sub>2</sub> ="; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter }
                                            Text { 
                                                text: formatAdaptive(pendulumObj.omega2, 3, 1) + " рад/с"; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter; 
                                                elide: Text.ElideRight }
                                        }
                                    }
                                }
                                
                                // Separator for parameter input section
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    Layout.topMargin: 16
                                    Layout.bottomMargin: 32
                                    color: mainWindow.isDarkTheme ? "#505050" : "#D0D0D0"
                                }
                                
                                // Parameter input grid
                                GridLayout {
                                    id: parameterInputGrid
                                    columns: 3
                                    columnSpacing: 20
                                    rowSpacing: 10 // Will be spacing between rows of logical columns, if any.
                                    Layout.alignment: Qt.AlignHCenter // Center the grid itself if it doesn't fill width
                                    Layout.fillWidth: true // The grid will attempt to fill available width

                                    // Logical Column 1 (m1, m2, b1, b2, omega10)
                                    ColumnLayout {
                                        // Layout.fillWidth: true // Let GridLayout handle width distribution
                                         Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                                        spacing: 8 // Vertical spacing within this logical column

                                        RowLayout {
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText;
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0m<sub>1</sub>,\u00A0кг:"; 
                                                Layout.preferredWidth: 60; color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                                } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: m1Input; 
                                                    property int decimals: 2; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.m1 * decimalFactor) : Math.round(1.0 * decimalFactor); 
                                                    from: 0.01 * decimalFactor; 
                                                    to: 30.0 * decimalFactor; 
                                                    stepSize: Number(0.1 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        var realDisplayValue = value / decimalFactor; 
                                                        return Number(realDisplayValue).toLocaleString(locale, 'f', decimals);
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); if (isNaN(realNum)) return m1Input.value; 
                                                        var minReal = 0.01; var maxReal = 30.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.m1 - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset(); 
                                                                pendulumObj.m1 = realNewValue; 
                                                            } 
                                                        } 
                                                    } 
                                                } 
                                            } 
                                        }

                                        RowLayout { 
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0m<sub>2</sub>,\u00A0кг:"; 
                                                Layout.preferredWidth: 60; color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: m2Input; 
                                                    property int decimals: 2; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.m2 * decimalFactor) : Math.round(1.0 * decimalFactor); 
                                                    from: 0.01 * decimalFactor; 
                                                    to: 30.0 * decimalFactor; 
                                                    stepSize: Number(0.1 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        var realDisplayValue = value / decimalFactor; 
                                                        return Number(realDisplayValue).toLocaleString(locale, 'f', decimals);
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return m2Input.value; 
                                                        var minReal = 0.01; var maxReal = 30.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor);
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0";
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.m2 - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset(); 
                                                                pendulumObj.m2 = realNewValue; 
                                                            } 
                                                        } 
                                                    } 
                                                } 
                                            } 
                                        }

                                        RowLayout { 
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0b<sub>1</sub>:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter 
                                            } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: b1Input; 
                                                    property int decimals: 3; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.b1 * decimalFactor) : Math.round(0.1 * decimalFactor); 
                                                    from: 0.0 * decimalFactor; 
                                                    to: 5.0 * decimalFactor; 
                                                    stepSize: Number(0.01 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals); 
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace(" м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return b1Input.value; 
                                                        var minReal = 0.0; 
                                                        var maxReal = 5.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.b1 - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset(); 
                                                                pendulumObj.b1 = realNewValue; 
                                                            } 
                                                        } 
                                                    } 
                                                } 
                                            } 
                                        }

                                        RowLayout { 
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0b<sub>2</sub>:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: b2Input; 
                                                    property int decimals: 3; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.b2 * decimalFactor) : Math.round(0.1 * decimalFactor); 
                                                    from: 0.0 * decimalFactor; 
                                                    to: 5.0 * decimalFactor; 
                                                    stepSize: Number(0.01 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals);
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace(" м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return b2Input.value; 
                                                        var minReal = 0.0; 
                                                        var maxReal = 5.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.b2 - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset(); 
                                                                pendulumObj.b2 = realNewValue;
                                                            } 
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        RowLayout { 
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0ω<sub>1</sub>,\u00A0рад/с:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: initialOmega1Input; 
                                                    property int decimals: 3; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: Math.round(0.0 * decimalFactor) ; 
                                                    from: -50.0 * decimalFactor; 
                                                    to: 50.0 * decimalFactor; 
                                                    stepSize: Number(1 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals);
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) { 
                                                            return initialOmega1Input.value; 
                                                        } 
                                                        var minReal = -50.0; 
                                                        var maxReal = 50.0;  
                                                        if (realNum < minReal) realNum = minReal;
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        var internalValue = Math.round(realNum * decimalFactor); 
                                                        return internalValue; 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333";
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: {} 
                                                } 
                                            } 
                                        }
                                    }

                                    // Logical Column 2 (M1, M2, c1, c2, omega20)
                                    ColumnLayout {
                                        // Layout.fillWidth: true // Let GridLayout handle width distribution
                                        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                                        spacing: 8 // Vertical spacing within this logical column

                                        RowLayout { spacing: 3;
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0M<sub>1</sub>,\u00A0кг:"; 
                                                Layout.preferredWidth: 60; color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: m1RodInput; 
                                                    property int decimals: 2; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.m1_rod * decimalFactor) : Math.round(0.5 * decimalFactor); 
                                                    from: 0.0 * decimalFactor; 
                                                    to: 10.0 * decimalFactor; 
                                                    stepSize: Number(0.1 * decimalFactor); 
                                                    editable: true; textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals); 
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return m1RodInput.value; var minReal = 0.0;
                                                        var maxReal = 10.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.m1_rod - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset(); 
                                                                pendulumObj.m1_rod = realNewValue; 
                                                            } 
                                                        } 
                                                    } 
                                                }
                                            } 
                                        }

                                        RowLayout {  
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0M<sub>2</sub>,\u00A0кг:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: m2RodInput; 
                                                    property int decimals: 2; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.m2_rod * decimalFactor) : Math.round(0.5 * decimalFactor); 
                                                    from: 0.0 * decimalFactor; 
                                                    to: 10.0 * decimalFactor; 
                                                    stepSize: Number(0.1 * decimalFactor); 
                                                    editable: true; textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals); 
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return m2RodInput.value; 
                                                        var minReal = 0.0; 
                                                        var maxReal = 10.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.m2_rod - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset(); 
                                                                pendulumObj.m2_rod = realNewValue; 
                                                            } 
                                                        } 
                                                    } 
                                                } 
                                            }
                                        }
                                        RowLayout {  
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0c<sub>1</sub>:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: c1Input; 
                                                    property int decimals: 4; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.c1 * decimalFactor) : Math.round(0.05 * decimalFactor); 
                                                    from: 0.0 * decimalFactor; 
                                                    to: 1.0 * decimalFactor; 
                                                    stepSize: Number(0.001 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals); 
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return c1Input.value; 
                                                        var minReal = 0.0; 
                                                        var maxReal = 1.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.c1 - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset(); 
                                                                pendulumObj.c1 = realNewValue; 
                                                            } 
                                                        } 
                                                    } 
                                                } 
                                            }     
                                        }

                                        RowLayout {  
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0c<sub>2</sub>:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: c2Input; 
                                                    property int decimals: 4; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.c2 * decimalFactor) : Math.round(0.05 * decimalFactor); 
                                                    from: 0.0 * decimalFactor; 
                                                    to: 1.0 * decimalFactor; 
                                                    stepSize: Number(0.001 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals);
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return c2Input.value; 
                                                        var minReal = 0.0; 
                                                        var maxReal = 1.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.c2 - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset();
                                                                pendulumObj.c2 = realNewValue; 
                                                            } 
                                                        } 
                                                    } 
                                                } 
                                            } 
                                        }

                                        RowLayout {  
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0ω<sub>2</sub>,\u00A0рад/с:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: initialOmega2Input; 
                                                    property int decimals: 3; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: Math.round(0.0 * decimalFactor) ; 
                                                    from: -50.0 * decimalFactor; 
                                                    to: 50.0 * decimalFactor; 
                                                    stepSize: Number(1 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals); 
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) { 
                                                            return initialOmega2Input.value; 
                                                        } 
                                                        var minReal = -50.0; 
                                                        var maxReal = 50.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        var internalValue = Math.round(realNum * decimalFactor); 
                                                        return internalValue; 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: {} 
                                                } 
                                            } 
                                        }
                                    }

                                    // Logical Column 3 (l1, l2, theta10, theta20, g)
                                    ColumnLayout {
                                        // Layout.fillWidth: true // Let GridLayout handle width distribution
                                        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                                        spacing: 8 // Vertical spacing within this logical column

                                        RowLayout { 
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0l<sub>1</sub>,\u00A0м:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter 
                                            } 
                                            Item { 
                                                Layout.preferredWidth: 78;
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: l1Input; 
                                                    property int decimals: 2; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.l1 * decimalFactor) : Math.round(1.0 * decimalFactor); 
                                                    from: 0.1 * decimalFactor; 
                                                    to: 5.0 * decimalFactor; 
                                                    stepSize: Number(0.1 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        var realDisplayValue = value / decimalFactor; 
                                                        return Number(realDisplayValue).toLocaleString(locale, 'f', decimals); 
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return l1Input.value; 
                                                        var minReal = 0.1; 
                                                        var maxReal = 5.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.l1 - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset(); 
                                                                pendulumObj.l1 = realNewValue; 
                                                            } 
                                                        } 
                                                    } 
                                                } 
                                            } 
                                        }

                                        RowLayout {  
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0l<sub>2</sub>,\u00A0м:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter 
                                            } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: l2Input; 
                                                    property int decimals: 2; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.l2 * decimalFactor) : Math.round(1.0 * decimalFactor); 
                                                    from: 0.1 * decimalFactor; 
                                                    to: 5.0 * decimalFactor; 
                                                    stepSize: Number(0.1 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals); 
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("+\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return l2Input.value; 
                                                        var minReal = 0.1; 
                                                        var maxReal = 5.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.l2 - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset(); 
                                                                pendulumObj.l2 = realNewValue; 
                                                            } 
                                                        } 
                                                    } 
                                                } 
                                            }                                                            
                                        }
                                        RowLayout { 
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0θ<sub>1</sub>,\u00A0°:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: initialTheta1AbsInput; 
                                                    property int decimals: 1; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: Math.round(45.0 * decimalFactor); 
                                                    from: -720.0 * decimalFactor; 
                                                    to: 720.0 * decimalFactor; 
                                                    stepSize: Number(1.0 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals);
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return initialTheta1AbsInput.value; 
                                                        var minReal = -36000.0; 
                                                        var maxReal = 36000.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: {} 
                                                } 
                                            } 
                                        }
                                        
                                        RowLayout {  
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0θ<sub>2</sub>,\u00A0°:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: initialTheta2AbsInput; 
                                                    property int decimals: 1; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: Math.round(90.0 * decimalFactor); 
                                                    from: -720.0 * decimalFactor; 
                                                    to: 720.0 * decimalFactor; 
                                                    stepSize: Number(1 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: 
                                                    function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals);
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) { 
                                                            return initialTheta2AbsInput.value; 
                                                        } 
                                                        var minReal = -36000.0; 
                                                        var maxReal = 36000.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        var internalValue = Math.round(realNum * decimalFactor); 
                                                        return internalValue; 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: {} 
                                                } 
                                            } 
                                        }

                                        RowLayout { 
                                            spacing: 3; 
                                            Text { 
                                                textFormat: Text.RichText; 
                                                text: "\u00A0\u00A0\u00A0\u00A0\u00A0g,\u00A0м/с²:"; 
                                                Layout.preferredWidth: 60; 
                                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                font.pixelSize: 12; 
                                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter } 
                                            Item { 
                                                Layout.preferredWidth: 78; 
                                                Layout.preferredHeight: 22; 
                                                Layout.alignment: Qt.AlignLeft; 
                                                SpinBox { 
                                                    id: gInput; 
                                                    property int decimals: 2; 
                                                    readonly property int decimalFactor: Math.pow(10, decimals); 
                                                    value: pendulumObj ? Math.round(pendulumObj.g * decimalFactor) : Math.round(9.81 * decimalFactor); 
                                                    from: 0.0 * decimalFactor; 
                                                    to: 100.0 * decimalFactor; 
                                                    stepSize: Number(0.1 * decimalFactor); 
                                                    editable: true; 
                                                    textFromValue: function(value, locale) { 
                                                        return Number(value / decimalFactor).toLocaleString(locale, 'f', decimals); 
                                                    }; 
                                                    valueFromText: function(text, locale) { 
                                                        var cleanedText = String(text).replace("°", "").replace("\u00A0рад/с", "").replace("\u00A0м/с²", "").replace("\u00A0м", "").replace("\u00A0кг", "").replace(",", ".").trim(); 
                                                        var realNum = parseFloat(cleanedText); 
                                                        if (isNaN(realNum)) return gInput.value; 
                                                        var minReal = 0.0; 
                                                        var maxReal = 100.0; 
                                                        if (realNum < minReal) realNum = minReal; 
                                                        else if (realNum > maxReal) realNum = maxReal; 
                                                        return Math.round(realNum * decimalFactor); 
                                                    }; 
                                                    anchors.fill: parent; 
                                                    font.pixelSize: 12; 
                                                    padding: 2; 
                                                    palette.text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    palette.base: mainWindow.isDarkTheme ? "#2D2D2D" : "#FFFFFF"; 
                                                    palette.button: mainWindow.isDarkTheme ? "#4F4F4F" : "#F0F0F0"; 
                                                    palette.buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                                    onValueChanged: { 
                                                        if (typeof value === 'number' && pendulumObj) { 
                                                            var realNewValue = value / decimalFactor; 
                                                            if (Math.abs(pendulumObj.g - realNewValue) > 1e-9) { 
                                                                finalizeAllPoincareSeriesBeforeReset(); 
                                                                pendulumObj.g = realNewValue; 
                                                            } 
                                                        } 
                                                    } 
                                                } 
                                            } 
                                        }
                                    }
                                }
                                
                                // Connections for updating from pendulumObj to controls
                                Connections {
                                    target: pendulumObj
                                    function onM1Changed() {
                                        if (m1Input && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.m1;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * m1Input.decimalFactor);
                                            if (m1Input.value !== spinBoxShouldDisplayInternalValue) {
                                                m1Input.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                    function onM2Changed() {
                                        if (m2Input && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.m2;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * m2Input.decimalFactor);
                                            if (m2Input.value !== spinBoxShouldDisplayInternalValue) {
                                                m2Input.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                    function onM1_rodChanged() {
                                        if (m1RodInput && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.m1_rod;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * m1RodInput.decimalFactor);
                                            if (m1RodInput.value !== spinBoxShouldDisplayInternalValue) {
                                                m1RodInput.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                    function onM2_rodChanged() {
                                        if (m2RodInput && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.m2_rod;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * m2RodInput.decimalFactor);
                                            if (m2RodInput.value !== spinBoxShouldDisplayInternalValue) {
                                                m2RodInput.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                    function onL1Changed() {
                                        if (l1Input && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.l1;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * l1Input.decimalFactor);
                                            if (l1Input.value !== spinBoxShouldDisplayInternalValue) {
                                                l1Input.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                    function onL2Changed() {
                                        if (l2Input && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.l2;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * l2Input.decimalFactor);
                                            if (l2Input.value !== spinBoxShouldDisplayInternalValue) {
                                                l2Input.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                    function onB1Changed() {
                                        if (b1Input && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.b1;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * b1Input.decimalFactor);
                                            if (b1Input.value !== spinBoxShouldDisplayInternalValue) {
                                                b1Input.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                    function onB2Changed() {
                                        if (b2Input && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.b2;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * b2Input.decimalFactor);
                                            if (b2Input.value !== spinBoxShouldDisplayInternalValue) {
                                                b2Input.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                    function onC1Changed() {
                                        if (c1Input && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.c1;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * c1Input.decimalFactor);
                                            if (c1Input.value !== spinBoxShouldDisplayInternalValue) {
                                                c1Input.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                    function onC2Changed() {
                                        if (c2Input && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.c2;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * c2Input.decimalFactor);
                                            if (c2Input.value !== spinBoxShouldDisplayInternalValue) {
                                                c2Input.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                    function onGChanged() {
                                        if (gInput && pendulumObj) {
                                            var realValueFromCpp = pendulumObj.g;
                                            var spinBoxShouldDisplayInternalValue = Math.round(realValueFromCpp * gInput.decimalFactor);
                                            if (gInput.value !== spinBoxShouldDisplayInternalValue) {
                                                gInput.value = spinBoxShouldDisplayInternalValue;
                                            }
                                        }
                                    }
                                }
                                
                                // Point Masses group
                                Item {
                                    Layout.fillWidth: true // Занимает ширину
                                    Layout.preferredHeight: 12 // Высота отступа
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Timer to update the simulation
    Timer {
        id: simulationTimer
        interval: {
            if (mainWindow.limitFpsEnabled && mainWindow.targetMaxFps > 0) {
                return Math.round(1000 / mainWindow.targetMaxFps);
            } else {
                return 16; // Default ~60 FPS
            }
        }
        running: false
        repeat: true
        onTriggered: {
            if (mainWindow.pendulumObj) {
                mainWindow.pendulumObj.step(interval / 1000.0); // dt in seconds
                mainWindow.frameCount++; // Increment frameCount here
                
                // Update trace paths only when needed (every 5th frame to optimize performance)
                if (pendulumCanvas && pendulumCanvas.visible && pendulumCanvas.available) {
                    // We rely on the Connections to pendulumObj.onStateChanged to update the off-screen traces
                    // No need to call redrawOffscreenTraces() directly here
                }
            }
        }
    }

    // Add simulation failure handling
    Connections {
        target: pendulumObj
        function onSimulationFailedChanged() {
            if (pendulumObj.simulationFailed) {
                simulationTimer.stop();
                startStopButton.text = "Start";
            }
        }
    }

    // Initial check
    Component.onCompleted: {
        // Установка начальных значений для SpinBox'ов
        if (m1Input) m1Input.value = Math.round(1.0 * m1Input.decimalFactor);
        if (m2Input) m2Input.value = Math.round(1.0 * m2Input.decimalFactor);
        if (m1RodInput) m1RodInput.value = Math.round(0.5 * m1RodInput.decimalFactor);
        if (m2RodInput) m2RodInput.value = Math.round(0.5 * m2RodInput.decimalFactor);
        if (l1Input) l1Input.value = Math.round(1.0 * l1Input.decimalFactor);
        if (l2Input) l2Input.value = Math.round(1.0 * l2Input.decimalFactor); 
        if (b1Input) b1Input.value = Math.round(0.1 * b1Input.decimalFactor); 
        if (b2Input) b2Input.value = Math.round(0.1 * b2Input.decimalFactor); 
        if (c1Input) c1Input.value = Math.round(0.05 * c1Input.decimalFactor); 
        if (c2Input) c2Input.value = Math.round(0.05 * c2Input.decimalFactor); 
        if (gInput) gInput.value = Math.round(9.81 * gInput.decimalFactor);

        if (initialTheta1AbsInput) initialTheta1AbsInput.value = Math.round(45.0 * initialTheta1AbsInput.decimalFactor);
        if (initialTheta2AbsInput) initialTheta2AbsInput.value = Math.round(90.0 * initialTheta2AbsInput.decimalFactor);
        if (initialOmega1Input) initialOmega1Input.value = Math.round(0.0 * initialOmega1Input.decimalFactor);
        if (initialOmega2Input) initialOmega2Input.value = Math.round(0.0 * initialOmega2Input.decimalFactor);

        // Затем вызываем reset, чтобы pendulumObj получил эти значения
        if (mainWindow.pendulumObj && 
            m1Input && m2Input && m1RodInput && m2RodInput && l1Input && l2Input &&
            b1Input && b2Input && c1Input && c2Input && gInput &&
            initialTheta1AbsInput && initialTheta2AbsInput && initialOmega1Input && initialOmega2Input) {
            // console.log("Main.qml onCompleted: Applying initial conditions from SpinBoxes to C++ pendulum.");
            resetPendulumWithCurrentValues(); 
            
            // Устанавливаем глянцевый материал по умолчанию при запуске
            applyMaterialToPendulum(polishedAluminumMaterial);
        } else {
            // console.error("Main.qml onCompleted: Could not apply initial conditions. One or more SpinBoxes might be missing.");
        }

        // Запрашиваем первую отрисовку, когда все точно готово.
        if (pendulumCanvas) {
            // Откладываем вызов до следующего цикла событий, когда Canvas будет гарантированно готов.
            Qt.callLater(function() { 
                if (pendulumCanvas.available) {
                    pendulumCanvas.requestPaint(); 
                }
            });
        }
    }

    // Master timer for updating all charts
    Timer {
        id: masterChartUpdateTimer
        interval: 100 // Update charts 10 times per second
        repeat: true
        running: mainWindow.analysisModeActive && simulationTimer.running
        onTriggered: {
            if (chartsColumnLayout) {
                for (var i = 0; i < chartsColumnLayout.children.length; ++i) {
                    var chartPlaceholder = chartsColumnLayout.children[i];
                    // Update only visible charts
                    if (chartPlaceholder && chartPlaceholder.visible && typeof chartPlaceholder.updateChartDataAndPaint === "function") {
                        chartPlaceholder.updateChartDataAndPaint();
                    }
                }
            }
        }
    }

    // Dialog for settings
    Dialog {
        id: settingsDialog
        title: qsTr("Настройки")
        width: 360
        height: 325 
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        
        // --- Прокси-свойства для временного хранения настроек ---
        property bool proxyAntialiasing: false
        property int  proxyAaQuality: 0 // Это всегда будет INT
        property bool proxyReflections: false
        property bool proxyShowFps: false
        
        // --- Стилизация (без изменений) ---
        background: Rectangle { color: mainWindow.isDarkTheme ? "#424242" : "#F8F8F8"; border.color: mainWindow.isDarkTheme ? "#555555" : "#D0D0D0"; border.width: 1; radius: 4 }
        header: Rectangle { color: "transparent"; height: 40; width: parent.width; Text { text: settingsDialog.title; anchors.centerIn: parent; font.bold: true; font.pixelSize: 16; color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333" } }
        palette { window: mainWindow.isDarkTheme ? "#424242" : "#F8F8F8"; windowText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; text: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; buttonText: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; button: mainWindow.isDarkTheme ? "#505050" : "#E5E5E5" }

        // --- ПОЛНОСТЬЮ НОВАЯ ЛОГИКА ---
        
        onVisibleChanged: {
            if (visible) {
                // 1. Считываем текущее состояние приложения
                if (!view3D || !view3D.environment || !pendulum3DModel) return;

                proxyAntialiasing = (view3D.environment.antialiasingMode !== SceneEnvironment.NoAA);
                // ИСПРАВЛЕНО: Преобразуем enum в новый индекс
                proxyAaQuality = qualityToIndex(view3D.environment.antialiasingQuality);
                
                var partToCheck = findNodeByName(pendulum3DModel, "bob1");
                if (partToCheck && partToCheck.materials.length > 0) {
                    proxyReflections = (partToCheck.materials[0].metalness > 0.5);
                }
                proxyShowFps = mainWindow.fpsCounterVisible;

                // 2. Устанавливаем значения для UI
                aaCheckbox.checked = proxyAntialiasing;
                aaQualityComboBox.currentIndex = proxyAaQuality;
                reflectionsCheckbox.checked = proxyReflections;
                showFpsCheckbox.checked = proxyShowFps;
            }
        }

        onAccepted: {
            // ИСПРАВЛЕНО: Преобразуем новый индекс обратно в enum
            if (view3D && view3D.environment) {
                view3D.environment.antialiasingMode = proxyAntialiasing ? SceneEnvironment.MSAA : SceneEnvironment.NoAA;
                view3D.environment.antialiasingQuality = indexToQuality(proxyAaQuality);
            }
            
            var targetMaterial = proxyReflections ? polishedAluminumMaterial : matteGrayMaterial;
            mainWindow.applyMaterialToPendulum(targetMaterial);
            mainWindow.fpsCounterVisible = proxyShowFps;
        }
        
        // onRejected остается пустым, так как мы ничего не меняем до нажатия "OK"
        
        // --- Содержимое диалога с двусторонними привязками к прокси-свойствам ---
        ScrollView {
            anchors.fill: parent
            anchors.margins: 10
            clip: true
            
            Column {
                width: parent.width
                spacing: 15
                
                GroupBox {
                    title: "Настройки 3D-графики"
                    width: parent.width
                    label: Label { text: parent.title; color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; font.bold: true }
                    background: Rectangle { color: "transparent" }

                    Column {
                        width: parent.width
                        spacing: 10
                        
                        CheckBox {
                            id: aaCheckbox
                            text: "Сглаживание (Antialiasing)"
                            checked: settingsDialog.proxyAntialiasing
                            onCheckedChanged: settingsDialog.proxyAntialiasing = checked
                            
                            indicator: Rectangle { 
                                width: 18; height: 18; radius: 4;
                                x: parent.leftPadding;
                                y: parent.topPadding + (parent.availableHeight - height) / 2;
                                
                                // ИЗМЕНЕНО: Фон теперь нейтральный
                                color: parent.checked ? (mainWindow.isDarkTheme ? "#6E6E6E" : "#777777") : "transparent";
                                border.color: mainWindow.isDarkTheme ? "#AAAAAA" : "#777777";
                                border.width: 2;
                                Behavior on color { ColorAnimation { duration: 150 } }
                                
                                // ДОБАВЛЕНО: Текстовая галочка для ясности
                                Text {
                                    text: "✓"
                                    anchors.centerIn: parent
                                    // ИСПРАВЛЕНО: Явная привязка к id
                                    visible: aaCheckbox.checked
                                    color: mainWindow.isDarkTheme ? "#FFFFFF" : "#FFFFFF"
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }
                            contentItem: Text { text: parent.text; font: parent.font; color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; verticalAlignment: Text.AlignVCenter; leftPadding: parent.indicator.width + parent.spacing }
                        }

                        RowLayout {
                            width: parent.width
                            enabled: aaCheckbox.checked
                            spacing: 5 // Отступ между элементами

                            Label {
                                text: "Качество:"
                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"
                                Layout.alignment: Qt.AlignVCenter
                                opacity: parent.enabled ? 1.0 : 0.5
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                            
                            ComboBox {
                                id: aaQualityComboBox
                                Layout.preferredWidth: 150 // Увеличим ширину для новых названий
                                Layout.preferredHeight: 28 // Увеличенная высота
                                // ИСПРАВЛЕНО: Убрали "Низкое" из модели
                                model: ["Среднее", "Высокое", "Очень высокое"]
                                
                                // Жесткая двусторонняя привязка к int свойству
                                currentIndex: settingsDialog.proxyAaQuality
                                onCurrentIndexChanged: settingsDialog.proxyAaQuality = currentIndex
                                
                                palette.text: parent.enabled ? (mainWindow.isDarkTheme ? "#E0E0E0" : "#222222") : (mainWindow.isDarkTheme ? "#888888" : "#AAAAAA")
                                contentItem: Text { 
                                    text: parent.displayText // Возвращаем к стандартному поведению
                                    font: parent.font 
                                    color: parent.palette.text 
                                    verticalAlignment: Text.AlignVCenter 
                                    horizontalAlignment: Text.AlignHCenter 
                                    elide: Text.ElideRight 
                                }
                                background: Rectangle { color: mainWindow.isDarkTheme ? "#444444" : "#DDDDDD"; radius: 3; border.color: mainWindow.isDarkTheme ? "#666666" : "#BBBBBB"; border.width: 1; opacity: parent.enabled ? 1.0 : 0.5; Behavior on opacity { NumberAnimation { duration: 150 } } }
                                popup: Popup { y: aaQualityComboBox.height; width: aaQualityComboBox.width; implicitHeight: contentItem.implicitHeight; padding: 1; contentItem: ListView { clip: true; implicitHeight: contentHeight; model: aaQualityComboBox.popup.visible ? aaQualityComboBox.delegateModel : null; currentIndex: aaQualityComboBox.highlightedIndex; ScrollIndicator.vertical: ScrollIndicator { } } background: Rectangle { color: mainWindow.isDarkTheme ? "#444444" : "#FFFFFF"; border.color: mainWindow.isDarkTheme ? "#666666" : "#BBBBBB"; border.width: 1; radius: 2 } }
                                delegate: ItemDelegate { 
                                    width: aaQualityComboBox.width
                                    contentItem: Text { 
                                        text: modelData; 
                                        color: mainWindow.isDarkTheme ? "#E0E0E0" : "#222222"; 
                                        font: aaQualityComboBox.font; 
                                        elide: Text.ElideRight; 
                                        verticalAlignment: Text.AlignVCenter; 
                                        horizontalAlignment: Text.AlignHCenter; 
                                        width: parent.width 
                                    } 
                                    highlighted: aaQualityComboBox.highlightedIndex === index; 
                                    background: Rectangle { 
                                        color: highlighted ? (mainWindow.isDarkTheme ? "#666666" : "#DDDDDD") : (mainWindow.isDarkTheme ? "#444444" : "#FFFFFF") 
                                    }
                                }
                            }
                            
                            // Пустой элемент-распорка, чтобы все остальное ушло вправо
                            Item { Layout.fillWidth: true } 
                        }

                        CheckBox {
                            id: reflectionsCheckbox
                            text: "Включить отражения и блики"
                            checked: settingsDialog.proxyReflections
                            onCheckedChanged: settingsDialog.proxyReflections = checked
                            
                            indicator: Rectangle {
                                width: 18; height: 18; radius: 4;
                                x: parent.leftPadding;
                                y: parent.topPadding + (parent.availableHeight - height) / 2;
                                
                                // ИЗМЕНЕНО: Фон теперь нейтральный
                                color: parent.checked ? (mainWindow.isDarkTheme ? "#6E6E6E" : "#777777") : "transparent";
                                border.color: mainWindow.isDarkTheme ? "#AAAAAA" : "#777777";
                                border.width: 2;
                                Behavior on color { ColorAnimation { duration: 150 } }
                                
                                // ДОБАВЛЕНО: Текстовая галочка для ясности
                                Text {
                                    text: "✓"
                                    anchors.centerIn: parent
                                    // ИСПРАВЛЕНО: Явная привязка к id
                                    visible: reflectionsCheckbox.checked
                                    color: mainWindow.isDarkTheme ? "#FFFFFF" : "#FFFFFF"
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }
                            contentItem: Text { 
                                text: parent.text; 
                                font: parent.font; 
                                color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; 
                                verticalAlignment: Text.AlignVCenter; 
                                leftPadding: parent.indicator.width + parent.spacing 
                            }
                        }
                    }
                }
                
                GroupBox {
                    title: "Настройки симуляции"
                    width: parent.width
                    label: Label { text: parent.title; color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; font.bold: true }
                    background: Rectangle { color: "transparent" }

                    Column {
                        width: parent.width
                        spacing: 10
                        
                        CheckBox {
                            id: showFpsCheckbox
                            text: "Показывать FPS"
                            checked: settingsDialog.proxyShowFps
                            onCheckedChanged: settingsDialog.proxyShowFps = checked
                            
                            indicator: Rectangle { 
                                width: 18; height: 18; radius: 4;
                                x: parent.leftPadding;
                                y: parent.topPadding + (parent.availableHeight - height) / 2;
                                
                                // ИЗМЕНЕНО: Фон теперь нейтральный
                                color: parent.checked ? (mainWindow.isDarkTheme ? "#6E6E6E" : "#777777") : "transparent";
                                border.color: mainWindow.isDarkTheme ? "#AAAAAA" : "#777777";
                                border.width: 2;
                                Behavior on color { ColorAnimation { duration: 150 } }
                                
                                // ДОБАВЛЕНО: Текстовая галочка для ясности
                                Text {
                                    text: "✓"
                                    anchors.centerIn: parent
                                    // ИСПРАВЛЕНО: Явная привязка к id
                                    visible: showFpsCheckbox.checked
                                    color: mainWindow.isDarkTheme ? "#FFFFFF" : "#FFFFFF"
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }
                            contentItem: Text { text: parent.text; font: parent.font; color: mainWindow.isDarkTheme ? "#E0E0E0" : "#333333"; verticalAlignment: Text.AlignVCenter; leftPadding: parent.indicator.width + parent.spacing }
                        }
                    }
                }
            }
        }
    }

    // FileDialog for exporting 2D trace as PNG
    FileDialog {
        id: traceSaveDialog
        title: "Сохранить 2D траектории маятника"
        fileMode: FileDialog.SaveFile
        nameFilters: ["PNG Images (*.png)"]
        defaultSuffix: "png" // Added for convenience
        
        onAccepted: {
            // Получаем путь и преобразуем его в локальный путь
            var selectedFile = traceSaveDialog.selectedFile;
            var localFilePath = "";
            
            // Преобразуем URL в локальный путь
            if (typeof selectedFile === 'object' && typeof selectedFile.toString === 'function') {
                // Если это объект URL, преобразуем его в строку
                var urlString = selectedFile.toString();
                
                // Удаляем "file:///" префикс
                if (urlString.startsWith("file:///")) {
                    localFilePath = urlString.substring(Qt.platform.os === "windows" ? 8 : 7); // Windows: file:///C:/ -> C:/, Linux/macOS: file:/// -> /
                } else if (urlString.startsWith("file://")) {
                    localFilePath = urlString.substring(7); // Пропускаем "file://"
                } else {
                    localFilePath = urlString;
                }
            } else if (typeof selectedFile === 'string') {
                // Если это уже строка, проверяем, не URL ли это
                if (selectedFile.startsWith("file:///")) {
                    localFilePath = selectedFile.substring(Qt.platform.os === "windows" ? 8 : 7);
                } else if (selectedFile.startsWith("file://")) {
                    localFilePath = selectedFile.substring(7);
                } else {
                    localFilePath = selectedFile;
                }
            } else {
                console.error("QML: Unexpected type for selectedFile in traceSaveDialog:", typeof selectedFile);
                return;
            }
            
            // Ensure .png extension
            if (!localFilePath.toLowerCase().endsWith(".png")) {
                localFilePath += ".png";
            }
            
            console.log("TraceSaveDialog: Attempting to save to local path:", localFilePath);
            
            // 1. Ensure offscreen trace canvases contain complete updated traces
            // No need for preprocessing, we draw traces directly from data
            
            // 2. Request paint for the export canvas to display current traces
            combinedTracesExportCanvas.requestPaint();
            
            // 3. Capture the image from the combined canvas
            // grabToImage is asynchronous; its callback will be called when combinedTracesExportCanvas is ready
            Qt.callLater(function() { // Give the event loop a chance to process requestPaint
                combinedTracesExportCanvas.grabToImage(function(result) {
                    if (result.saveToFile(localFilePath)) {
                        console.log("Combined 2D Traces PNG saved to:", localFilePath);
                    } else {
                        console.error("Failed to save combined 2D Traces PNG to:", localFilePath);
                    }
                });
            });
        }
    }

    // В mainWindow добавляем свойство для управления сеткой
    property bool show2DGridAndAxes: false

    // Hidden canvas used for exporting only the trajectory traces
    Canvas {
        id: combinedTracesExportCanvas
        width: pendulumCanvas.width
        height: pendulumCanvas.height
        visible: false // This canvas should not be visible to the user
        antialiasing: true
        
        onPaint: {
            var ctx = getContext("2d");
            if (!ctx) return;
            
            ctx.fillStyle = mainWindow.isDarkTheme ? canvasContainer.color : canvasContainer.color;
            ctx.fillRect(0, 0, width, height);
            
            var visualState = pendulumCanvas.calculateVisualState(
                mainWindow.pendulumObj, width, height, pendulumCanvas.massScaleFactorForRadius
            );
            if (!visualState) return;

            var centerX = visualState.centerX;
            var centerY = visualState.centerY;

            if (mainWindow.show2DGridAndAxes) {
                var maxRadius = Math.min(width, height) * 0.42; // Используем 0.42 как и в основном канвасе
                ctx.strokeStyle = mainWindow.isDarkTheme ? "#6E6E6E" : "#CCCCCC";
                ctx.lineWidth = 0.5;

                [maxRadius * 0.25, maxRadius * 0.5, maxRadius * 0.75, maxRadius].forEach(function(r) {
                    ctx.beginPath(); ctx.arc(centerX, centerY, r, 0, 2 * Math.PI); ctx.stroke();
                });
                ctx.beginPath(); ctx.arc(centerX, centerY, visualState.l1_visual, 0, 2 * Math.PI); ctx.stroke();
                ctx.beginPath(); ctx.arc(centerX, centerY, visualState.l1_visual + visualState.l2_visual, 0, 2 * Math.PI); ctx.stroke();

                [-135, -120, -90, -60, -45, -30, 0, 30, 45, 60, 90, 120, 135, 180].forEach(function(degAngle) {
                    var radAngle = degAngle * Math.PI / 180;
                    ctx.beginPath(); ctx.moveTo(centerX, centerY);
                    var xEnd = centerX + maxRadius * Math.sin(radAngle);
                    var yEnd = centerY + maxRadius * Math.cos(radAngle);
                    ctx.lineTo(xEnd, yEnd); ctx.stroke();
                    
                    // --- ИЗМЕНЕНИЕ: Уменьшаем радиус для текста ---
                    var textRadius = maxRadius + 20; // Уменьшено с 12 до 10
                    var xT = centerX + textRadius * Math.sin(radAngle);
                    var yT = centerY + textRadius * Math.cos(radAngle);
                    
                    ctx.fillStyle = mainWindow.isDarkTheme ? "#C0C0C0" : "#555555";
                    ctx.font = "10px sans-serif";
                    
                    if (degAngle === 0) { ctx.textAlign = "center"; ctx.textBaseline = "top"; yT += 2; }
                    else if (degAngle === 180 || degAngle === -180) { ctx.textAlign = "center"; ctx.textBaseline = "bottom"; yT -= 2; }
                    else if (degAngle === 90) { ctx.textAlign = "left"; ctx.textBaseline = "middle"; xT += 2; }
                    else if (degAngle === -90) { ctx.textAlign = "right"; ctx.textBaseline = "middle"; xT -= 2; }
                    else if (degAngle > -90 && degAngle < 90) { ctx.textAlign = (degAngle < 0 ? "right" : "left"); ctx.textBaseline = "middle"; xT += (degAngle < 0 ? -2 : 2); }
                    else { ctx.textAlign = (degAngle < -90 ? "right" : "left"); ctx.textBaseline = "middle"; xT += (degAngle < -90 ? -2 : 2); }
                    
                    var labelText = degAngle === 0 ? "0°" : (degAngle > 0 ? "+" + degAngle + "°" : degAngle + "°");
                    ctx.fillText(labelText, xT, yT);
                });
            }

            if (mainWindow.showBob2RelativeGrid) {
                var bob1x = visualState.x1;
                var bob1y = visualState.y1;
                var l2_vis = visualState.l2_visual;
                ctx.strokeStyle = "#FF0000";
                ctx.lineWidth = 0.5;

                ctx.beginPath(); ctx.arc(bob1x, bob1y, l2_vis, 0, 2 * Math.PI); ctx.stroke();

                [-135, -120, -90, -60, -45, -30, 0, 30, 45, 60, 90, 120, 135, 180].forEach(function(degAngle) {
                    var radAngle = degAngle * Math.PI / 180;
                    ctx.beginPath(); ctx.moveTo(bob1x, bob1y);
                    var xEnd = bob1x + l2_vis * Math.sin(radAngle);
                    var yEnd = bob1y + l2_vis * Math.cos(radAngle);
                    ctx.lineTo(xEnd, yEnd); ctx.stroke();
                    
                    // --- ИЗМЕНЕНИЕ: Уменьшаем радиус для текста ---
                    var textRadius = l2_vis + 7; // Уменьшено с 8 до 5
                    var xT = bob1x + textRadius * Math.sin(radAngle);
                    var yT = bob1y + textRadius * Math.cos(radAngle);
                    
                    ctx.fillStyle = "#FF0000";
                    ctx.font = "8px sans-serif"; // Уменьшено с 8px до 7px
                    
                    if (degAngle === 0) { ctx.textAlign = "center"; ctx.textBaseline = "top"; yT += 2; }
                    else if (degAngle === 180 || degAngle === -180) { ctx.textAlign = "center"; ctx.textBaseline = "bottom"; yT -= 2; }
                    else if (degAngle === 90) { ctx.textAlign = "left"; ctx.textBaseline = "middle"; xT += 2; }
                    else if (degAngle === -90) { ctx.textAlign = "right"; ctx.textBaseline = "middle"; xT -= 2; }
                    else if (degAngle > -90 && degAngle < 90) { ctx.textAlign = (degAngle < 0 ? "right" : "left"); ctx.textBaseline = "middle"; xT += (degAngle < 0 ? -2 : 2); }
                    else { ctx.textAlign = (degAngle < -90 ? "right" : "left"); ctx.textBaseline = "middle"; xT += (degAngle < -90 ? -2 : 2); }
                    
                    var labelText = degAngle === 0 ? "0°" : (degAngle > 0 ? "+" + degAngle + "°" : degAngle + "°");
                    ctx.fillText(labelText, xT, yT);
                });
            }
            
            if (pendulumObj && pendulumObj.showTrace1) {
                var trace1Data = pendulumObj.getTrace1Points();
                if (trace1Data && trace1Data.length > 1) {
                    ctx.beginPath();
                    ctx.moveTo(centerX + trace1Data[0].x * visualState.globalScaleFactor, centerY + trace1Data[0].y * visualState.globalScaleFactor);
                    for (var i = 1; i < trace1Data.length; ++i) {
                        ctx.lineTo(centerX + trace1Data[i].x * visualState.globalScaleFactor, centerY + trace1Data[i].y * visualState.globalScaleFactor);
                    }
                    ctx.strokeStyle = "rgba(255, 0, 0, 0.5)";
                    ctx.lineWidth = pendulumCanvas.traceLineWidth;
                    ctx.stroke();
                }
            }

            if (pendulumObj && pendulumObj.showTrace2) {
                var traceData = pendulumObj.getTrace2Points();
                if (traceData.length > 1) {
                    ctx.beginPath(); ctx.moveTo(centerX + traceData[0].x * visualState.globalScaleFactor, centerY + traceData[0].y * visualState.globalScaleFactor);
                    for (let i = 1; i < traceData.length; ++i) ctx.lineTo(centerX + traceData[i].x * visualState.globalScaleFactor, centerY + traceData[i].y * visualState.globalScaleFactor);
                    ctx.strokeStyle = mainWindow.isDarkTheme ? "rgba(100, 100, 255, 0.7)" : "rgba(0, 0, 255, 0.5)"; ctx.lineWidth = pendulumCanvas.traceLineWidth; ctx.stroke();
                }
            }
        }
    }

    // Calculate visual state for angles (used by both 2D and 3D visualizations)
    function calculateVisualState() {
        if (!pendulumObj) {
            console.error("calculateVisualState: pendulumObj is null");
            return;
        }

        // Get absolute and relative angles from pendulum object
        var t1_abs_rad = pendulumObj.theta1;
        var t2_rel_rad = pendulumObj.theta2;
        
        // Calculate absolute angle for the second pendulum (relative to global Y axis)
        var t2_abs_rad = t1_abs_rad + t2_rel_rad;
        
        // Debug logging for angles
        // console.log("calculateVisualState angles (rad): t1_abs=" + t1_abs_rad.toFixed(3) + 
        //           ", t2_rel=" + t2_rel_rad.toFixed(3) + ", t2_abs=" + t2_abs_rad.toFixed(3));
                      
        // console.log("calculateVisualState angles (deg): t1_abs=" + (t1_abs_rad * 180/Math.PI).toFixed(1) + 
        //           "°, t2_rel=" + (t2_rel_rad * 180/Math.PI).toFixed(1) + "°, t2_abs=" + (t2_abs_rad * 180/Math.PI).toFixed(1) + "°");
        
        // Common calculations for 2D and 3D coordinates
        var x0 = suspensionPointX;  // X coordinate of the suspension point
        var y0 = suspensionPointY;  // Y coordinate of the suspension point
        
        // Calculate 2D positions of the bobs
        var sin_t1 = Math.sin(t1_abs_rad);
        var cos_t1 = Math.cos(t1_abs_rad);
        var sin_t2 = Math.sin(t2_abs_rad);
        var cos_t2 = Math.cos(t2_abs_rad);
        
        // Calculate position of the first bob
        var x1_calc = x0 + rod1Length * sin_t1;
        var y1_calc = y0 + rod1Length * cos_t1;
        
        // Calculate position of the second bob
        var x2_calc = x1_calc + rod2Length * sin_t2;
        var y2_calc = y1_calc + rod2Length * cos_t2;
        
        // Calculate endpoint for the second bob relative grid (if visible)
        var grid_radius = 50;  // Radius for relative grid circle
        var grid_end_x = x2_calc + grid_radius * sin_t2;  // Extend in the direction of the second rod
        var grid_end_y = y2_calc + grid_radius * cos_t2;  // Extend in the direction of the second rod
        
        // Debug logging for calculated coordinates
        // console.log("calculateVisualState coords: bob1=(" + x1_calc.toFixed(1) + "," + y1_calc.toFixed(1) + 
        //           "), bob2=(" + x2_calc.toFixed(1) + "," + y2_calc.toFixed(1) + ")");
        
        // Return object with all calculated values
        return {
            // Angles (radians)
            theta1_abs: t1_abs_rad,
            theta2_abs: t2_abs_rad,
            theta2_rel: t2_rel_rad,
            
            // 2D coordinates
            x1: x1_calc,
            y1: y1_calc,
            x2: x2_calc,
            y2: y2_calc,
            
            // Relative grid endpoint
            grid_end_x: grid_end_x,
            grid_end_y: grid_end_y,
            
            // Trig cache values
            sin_t1: sin_t1,
            cos_t1: cos_t1,
            sin_t2: sin_t2,
            cos_t2: cos_t2
        };
    }

    // В начале файла Main.qml добавим стиль для GroupBox
    Component {
        id: themedGroupBoxStyle
        GroupBox {
            id: themedGroupBox
            property bool isDarkTheme: mainWindow.isDarkTheme
            
            label: Label {
                text: themedGroupBox.title
                color: themedGroupBox.isDarkTheme ? "#E0E0E0" : "#333333"
                wrapMode: Text.Wrap
            }
            
            background: Rectangle {
                color: themedGroupBox.isDarkTheme ? "#3A3A3A" : "#F5F5F5"
                border.color: themedGroupBox.isDarkTheme ? "#555555" : "#CCCCCC"
                border.width: 1
                radius: 4
            }
        }
    }
    
    // Help popup component
    HelpPopup {
        id: helpPopup
    }

    // Function to reset the pendulum with values from the controls
    function resetPendulumWithCurrentValues() {
        if (!pendulumObj) return;
        if (!m1Input || !m2Input || !m1RodInput || !m2RodInput || !l1Input || !l2Input ||
            !b1Input || !b2Input || !c1Input || !c2Input || !gInput ||
            !initialTheta1AbsInput || !initialTheta2AbsInput || !initialOmega1Input || !initialOmega2Input) {
            console.error("resetPendulumWithCurrentValues: One or more SpinBox controls are not defined. Aborting reset.");
            return;
        }

        // 1. Читаем ВСЕ значения из SpinBox'ов (с преобразованием из внутреннего формата)
        var val_m1 = m1Input.value / m1Input.decimalFactor;
        var val_m2 = m2Input.value / m2Input.decimalFactor;
        var val_M1 = m1RodInput.value / m1RodInput.decimalFactor;
        var val_M2 = m2RodInput.value / m2RodInput.decimalFactor;
        var val_l1 = l1Input.value / l1Input.decimalFactor;
        var val_l2 = l2Input.value / l2Input.decimalFactor; 
        var val_b1 = b1Input.value / b1Input.decimalFactor;
        var val_b2 = b2Input.value / b2Input.decimalFactor;
        var val_c1 = c1Input.value / c1Input.decimalFactor;
        var val_c2 = c2Input.value / c2Input.decimalFactor;
        var val_g  = gInput.value / gInput.decimalFactor;

        var t1_0_abs_deg_ui = initialTheta1AbsInput ? (initialTheta1AbsInput.value / initialTheta1AbsInput.decimalFactor) : 45.0; // Дефолт, если SpinBox не найден
        var t2_0_abs_deg_ui = initialTheta2AbsInput ? (initialTheta2AbsInput.value / initialTheta2AbsInput.decimalFactor) : 90.0; // Дефолт, если SpinBox не найден

        console.log("resetPendulumValues: Read from UI: t1_abs_deg_ui=" + t1_0_abs_deg_ui + ", t2_abs_deg_ui=" + t2_0_abs_deg_ui);

        var o1_0_rad_ui = initialOmega1Input ? (initialOmega1Input.value / initialOmega1Input.decimalFactor) : 0.0;
        var o2_0_rad_ui = initialOmega2Input ? (initialOmega2Input.value / initialOmega2Input.decimalFactor) : 0.0;

        var t1_0_abs_rad = t1_0_abs_deg_ui * Math.PI / 180.0;
        var t2_0_abs_rad = t2_0_abs_deg_ui * Math.PI / 180.0;

        // 2. Устанавливаем значения m1..g в pendulumObj
        pendulumObj.m1 = val_m1;
        pendulumObj.m2 = val_m2;
        pendulumObj.m1_rod = val_M1;
        pendulumObj.m2_rod = val_M2;
        pendulumObj.l1 = val_l1;
        pendulumObj.l2 = val_l2; 
        pendulumObj.b1 = val_b1;
        pendulumObj.b2 = val_b2;
        pendulumObj.c1 = val_c1;
        pendulumObj.c2 = val_c2;
        pendulumObj.g = val_g;

        // 3. Готовим углы для C++ reset
        var t2_0_rel_for_cpp = t2_0_abs_rad - t1_0_abs_rad;
        while (t2_0_rel_for_cpp > Math.PI) t2_0_rel_for_cpp -= 2 * Math.PI;
        while (t2_0_rel_for_cpp < -Math.PI) t2_0_rel_for_cpp += 2 * Math.PI;

        console.log("resetPendulumWithCurrentValues: About to call C++ reset with: t1_abs_rad=" + t1_0_abs_rad.toFixed(3) + 
                    ", o1_rad=" + o1_0_rad_ui.toFixed(3) + 
                    ", t2_rel_cpp=" + t2_0_rel_for_cpp.toFixed(3) + 
                    ", o2_rad=" + o2_0_rad_ui.toFixed(3));
        finalizeAllPoincareSeriesBeforeReset();
        pendulumObj.reset(t1_0_abs_rad, o1_0_rad_ui, t2_0_rel_for_cpp, o2_0_rad_ui);

        if (pendulumCanvas) {
            pendulumCanvas.clearTraces();
        }
    }
}

