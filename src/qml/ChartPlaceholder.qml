import QtQuick
import QtQuick.Controls 2.15
import QtQuick.Layouts
import QtQuick.Dialogs
import DoublePendulum 1.0 // Import the C++ module with enums

Rectangle {
    id: chartRoot
    // Это свойство будет устанавливаться при создании экземпляра
    property string chartTitle: "График"
    property bool isDarkTheme: false // По умолчанию светлая
    property bool themeJustChanged: false // Флаг для отслеживания изменений темы
    property bool forceFullChartRepaintDueToTheme: false // Флаг для двухпроходной перерисовки при смене темы
    
    signal themeChangedSignal() // Сигнал для уведомления о смене темы
    
    // Layout properties
    Layout.fillWidth: true // Чтобы занимал ширину chartsColumnLayout
    Layout.fillHeight: true // Занимать всю доступную высоту
    Layout.minimumHeight: 744 // Минимальная высота для отображения графика
    
    // Вспомогательная функция для "дергания" viewport'а
    function forceViewportUpdateForThemeChange() {
        if (xAxisSelector.currentText === "t, с") { // Только для временных рядов
            var originalAutoScroll = chartRoot.autoScrollToEnd;
            var originalMinX = chartRoot.viewPortMinX;
            var originalMaxX = chartRoot.viewPortMaxX;
            var smallChange = 0.000001;

            // 1. Явно отключаем автопрокрутку, как это происходит при ручном зуме/пане
            chartRoot.autoScrollToEnd = false;
            
            // 2. "Дергаем" viewport
            // Мы должны изменить и minX, и maxX, чтобы сохранить ширину окна,
            // иначе это будет интерпретировано как зум, а не как небольшое смещение.
            // Или, для простоты, просто сдвинем окно, а потом вернем.
            chartRoot.viewPortMinX = originalMinX + smallChange;
            chartRoot.viewPortMaxX = originalMaxX + smallChange;
            
            // 3. Вызываем основной метод обновления
            // Он должен пересчитать данные для нового viewport и запросить перерисовку
            updateChartDataAndPaint(); 
            
            // 4. Возвращаем значения viewport и autoScrollToEnd с помощью Qt.callLater,
            //    чтобы дать QML время обработать предыдущие изменения и перерисовку.
            //    Это важно, чтобы не "сломать" состояние, если пользователь действительно
            //    находился в режиме ручного масштабирования.
            Qt.callLater(function() {
                chartRoot.viewPortMinX = originalMinX;
                chartRoot.viewPortMaxX = originalMaxX;
                chartRoot.autoScrollToEnd = originalAutoScroll; // Восстанавливаем исходное состояние автопрокрутки
                // Еще один вызов updateChartDataAndPaint может понадобиться, если восстановление
                // viewport должно также привести к перерисовке с исходным масштабом.
                // Однако, если smallChange действительно мал, визуально разницы быть не должно.
                // На данном этапе попробуем без него, чтобы избежать лишних перерисовок.
                // Если тема обновилась, но масштаб "уехал" на smallChange, тогда нужно будет
                // добавить здесь еще один updateChartDataAndPaint().
                // console.log("Viewport and autoScrollToEnd restored after theme change nudge.");
            });

        } else {
            // Для других типов графиков (фазовые, Пуанкаре)
            lineChartCanvas.requestPaint();
        }
    }
    
    // Обработчик изменения темы
    onIsDarkThemeChanged: {
        console.log("chartRoot.onIsDarkThemeChanged FIRED. New theme isDark: " + isDarkTheme);
        if (chartRoot.visible && lineChartCanvas.width > 0 && lineChartCanvas.height > 0) {
            chartRoot.themeJustChanged = true; 
            lineChartCanvas.requestPaint(); // Запускаем первый проход
        }
    }
    
    // Обновленные цвета для светлой темы
    color: isDarkTheme ? "#2B2B2B" : "#F0F0F0"
    border.color: isDarkTheme ? "#555555" : "#D0D0D0"
    
    Behavior on color { ColorAnimation { duration: 400 } }
    Behavior on border.color { ColorAnimation { duration: 400 } }
    
    border.width: 1
    radius: 4
    
    // Ссылка на C++ объект
    property var pendulum: mainWindow.pendulumObj
    property list<point> chartData: []  // Данные для Canvas (для обычных графиков)
    property list<var> poincareSeriesList: [] // Список серий точек для карты Пуанкаре. Каждая серия - это объект { color: "код_цвета", points: [QPointF, ...] }
    property string currentChartType: "time_series_or_phase" // "time_series_or_phase", "poincare"
    property list<string> poincareColors: ["blue", "red", "green", "orange", "purple", "cyan", "magenta", "brown"]
    property int currentColorIndex: 0
    property real poincarePointRadius: 2.0 // Размер точек на карте Пуанкаре
    
    // Свойства для интерактивного масштабирования и панорамирования временных рядов
    property real viewPortMinX: 0.0         // Нижняя граница видимой области по X для временных рядов
    property real viewPortMaxX: 30.0        // Верхняя граница видимой области по X для временных рядов
    property bool isPanning: false          // Флаг состояния панорамирования
    property point lastPanPos               // Последняя позиция мыши при панорамировании
    property bool autoScrollToEnd: true     // Включено ли автоследование для временных рядов
    property real defaultTimeWindowWidth: 30.0 // Ширина окна по умолчанию в режиме следования (секунд)
    property real fullHistoryMinTime: 0.0   // Минимальное время во всей истории
    property real fullHistoryMaxTime: 0.0   // Максимальное время во всей истории
    
    // Эти свойства будут хранить фактические min/max значения области просмотра данных после всех вычислений
    property real effectiveMinX: 0
    property real effectiveMaxX: 1
    property real effectiveMinY: 0
    property real effectiveMaxY: 1
    
    // Флаг, указывающий, изменился ли масштаб или размеры графика с момента последнего цикла отрисовки
    property bool scaleOrChartSizeChanged: true
    
    // Флаг, указывающий, выполнено ли первоначальное обновление графика
    property bool initialUpdateDone: false
    
    // Для отслеживания изменений размеров холста
    property real prevCanvasWidth: 0
    property real prevCanvasHeight: 0
    
    // Обработчик изменения видимости
    onVisibleChanged: {
        if (visible && width > 0 && height > 0 && !chartRoot.initialUpdateDone) {
            // console.log("ChartPlaceholder (" + chartTitle + ") became visible with valid size. Performing initial update.");
            updateChartDataAndPaint();
            chartRoot.initialUpdateDone = true;
        }
    }
    
    // Функция для сохранения текущей серии точек карты Пуанкаре перед сбросом
    function finalizeCurrentPoincareSeries() {
        if (currentChartType === "poincare" && mainWindow.pendulumObj) {
            var currentPoints = mainWindow.pendulumObj.getPoincareMapPoints();
            if (poincareSeriesList.length > 0) {
                var activeSeriesIndex = poincareSeriesList.length - 1;
                // Вносим изменение: обновляем точки только если в C++ буфере есть новые точки,
                // иначе сохраняем уже существующие точки активной серии
                if (currentPoints.length > 0) {
                    poincareSeriesList[activeSeriesIndex].points = currentPoints; 
                    // console.log("Poincare series (color: " + poincareSeriesList[activeSeriesIndex].color + 
                    //             ") finalized with " + currentPoints.length + " points before reset/param change.");
                } else {
                    // console.log("Poincare series (color: " + poincareSeriesList[activeSeriesIndex].color + 
                    //             ") preserved with " + poincareSeriesList[activeSeriesIndex].points.length + 
                    //             " existing points (C++ buffer empty).");
                }
            }
            // После reset() в C++, getPoincareMapPoints() будет возвращать пустой список,
            // и при следующем переключении В режим Пуанкаре или клике на палитру начнется новая серия.
        }
    }
    
    // Replace the old getHistoryData function with a new one that uses the C++ optimized function
    function updateChartDataAndPaint() {
        if (!mainWindow.pendulumObj) return;

        // First, make sure we know the full time range of the simulation
        var fullHistoryForTime = pendulumObj.getTheta1History();
        if (fullHistoryForTime.length > 0) {
            chartRoot.fullHistoryMinTime = fullHistoryForTime[0].x;
            chartRoot.fullHistoryMaxTime = fullHistoryForTime[fullHistoryForTime.length - 1].x;
        } else {
            chartRoot.fullHistoryMinTime = 0;
            chartRoot.fullHistoryMaxTime = 0;
        }

        if (chartRoot.currentChartType === "poincare") {
            updateVisibleChart();
        } else {
            var finalDataForChart;
            var xAxisType = xAxisSelector.currentText;

            // --- LOGIC BRANCH FOR TIME SERIES ---
            if (xAxisType === 't, с') {
                // 1. Calculate the correct viewport
                if (chartRoot.autoScrollToEnd && chartRoot.fullHistoryMaxTime > 0) {
                    chartRoot.viewPortMinX = Math.max(0, chartRoot.fullHistoryMaxTime - chartRoot.defaultTimeWindowWidth);
                    chartRoot.viewPortMaxX = chartRoot.fullHistoryMaxTime;
                }

                // 2. Request data, WITH OPTIMIZATION SETTINGS from UI
                var ySeriesEnum;
                switch(yAxisSelector.currentText) {
                    case "θ₁, °":     ySeriesEnum = PendulumApi.Theta1_Degrees; break;
                    case "θ₂, °":     ySeriesEnum = PendulumApi.Theta2_Degrees; break;
                    case "ω₁, рад/с": ySeriesEnum = PendulumApi.Omega1_Rad_s; break;
                    case "ω₂, рад/с": ySeriesEnum = PendulumApi.Omega2_Rad_s; break;
                    case "T, Дж":     ySeriesEnum = PendulumApi.KineticEnergy; break;
                    case "V, Дж":     ySeriesEnum = PendulumApi.PotentialEnergy; break;
                    case "E, Дж":     ySeriesEnum = PendulumApi.TotalEnergy; break;
                    default:          ySeriesEnum = PendulumApi.Theta1_Degrees; // Default case
                }
                
                finalDataForChart = mainWindow.pendulumObj.getProcessedTimeSeriesData(
                    ySeriesEnum, // Now using the enum instead of string
                    chartRoot.viewPortMinX,
                    chartRoot.viewPortMaxX,
                    rdpEnabledCheckBox.checked,
                    rdpEpsilonSpinBox.value / 100.0,
                    limitPointsEnabledCheckBox.checked,
                    maxPointsSpinBox.value
                );

            } else {
                // --- LOGIC BRANCH FOR PHASE PORTRAITS (NEW & EFFICIENT) ---
                
                // Map X axis selection to series type enum
                var xSeriesEnum;
                switch(xAxisSelector.currentText) {
                    case "t, с":      xSeriesEnum = -1; break; // Should not happen in this branch
                    case "θ₁, °":     xSeriesEnum = PendulumApi.TimeSeriesType.Theta1_Degrees; break;
                    case "θ₂, °":     xSeriesEnum = PendulumApi.TimeSeriesType.Theta2_Degrees; break;
                    case "ω₁, рад/с": xSeriesEnum = PendulumApi.TimeSeriesType.Omega1_Rad_s; break;
                    case "ω₂, рад/с": xSeriesEnum = PendulumApi.TimeSeriesType.Omega2_Rad_s; break;
                }
                
                // Map Y axis selection to series type enum
                var ySeriesEnum;
                switch(yAxisSelector.currentText) {
                    case "θ₁, °":     ySeriesEnum = PendulumApi.TimeSeriesType.Theta1_Degrees; break;
                    case "θ₂, °":     ySeriesEnum = PendulumApi.TimeSeriesType.Theta2_Degrees; break;
                    case "ω₁, рад/с": ySeriesEnum = PendulumApi.TimeSeriesType.Omega1_Rad_s; break;
                    case "ω₂, рад/с": ySeriesEnum = PendulumApi.TimeSeriesType.Omega2_Rad_s; break;
                    case "T, Дж":      ySeriesEnum = PendulumApi.TimeSeriesType.KineticEnergy; break;
                    case "V, Дж":      ySeriesEnum = PendulumApi.TimeSeriesType.PotentialEnergy; break;
                    case "E, Дж":      ySeriesEnum = PendulumApi.TimeSeriesType.TotalEnergy; break;
                }

                // Get phase portrait data directly from C++ with a single call
                if (xSeriesEnum !== -1) {
                    finalDataForChart = mainWindow.pendulumObj.getPhasePortraitData(xSeriesEnum, ySeriesEnum);
                } else {
                    finalDataForChart = []; // Should not happen
                }
            }

            chartRoot.chartData = finalDataForChart;
        }

        // --- UNIFIED REPAINT BLOCK ---
        if (backgroundFeaturesCanvas.available) backgroundFeaturesCanvas.requestPaint();
        if (dataLineOffscreenCanvas.available) dataLineOffscreenCanvas.requestPaint();
        if (lineChartCanvas.available) lineChartCanvas.requestPaint();
    }
    
    // Функция для обновления видимой области графика
    function updateVisibleChart() {
        if (chartRoot.currentChartType === "poincare") {
            // В режиме карты Пуанкаре
            // Получаем данные карты Пуанкаре из C++ кода для текущей активной серии
            var currentPoincarePoints = mainWindow.pendulumObj.getPoincareMapPoints();
            
            // Обновляем или создаем активную серию с текущими точками
            if (chartRoot.poincareSeriesList.length === 0) {
                // Если нет серий, всегда создаем первую, даже если пока нет точек
                chartRoot.poincareSeriesList.push({
                    "color": chartRoot.poincareColors[chartRoot.currentColorIndex],
                    "points": currentPoincarePoints
                });
                
                // Запрашиваем перерисовку с безопасной проверкой доступности холстов
                if (dataLineOffscreenCanvas && dataLineOffscreenCanvas.available) {
                    dataLineOffscreenCanvas.requestPaint();
                }
                if (backgroundFeaturesCanvas && backgroundFeaturesCanvas.available) {
                    backgroundFeaturesCanvas.requestPaint();
                }
                return true; // Данные обновлены
            } else {
                // Обновляем точки последней (активной) серии только если есть новые точки
                var activeSeriesIndex = chartRoot.poincareSeriesList.length - 1;
                if (currentPoincarePoints.length > 0) {
                    chartRoot.poincareSeriesList[activeSeriesIndex].points = currentPoincarePoints;
                    
                    // Запрашиваем перерисовку с безопасной проверкой
                    if (dataLineOffscreenCanvas && dataLineOffscreenCanvas.available) {
                        dataLineOffscreenCanvas.requestPaint();
                    }
                    return true; // Данные обновлены
                }
            }
        }
        
        return false; // Данные не изменились
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 5 // Уменьшено с 10 до 5 для увеличения области графика
        spacing: 2 // Уменьшено с 5 до 2 для лучшего использования пространства

        // Кнопка закрытия графика теперь позиционируется в верхнем правом углу
        Button {
            id: closeButton
            text: ""
            icon.source: "qrc:/icons/cross.svg"
            icon.width: 16
            icon.height: 16
            icon.color: chartRoot.isDarkTheme ? "#CCCCCC" : "#333333"
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            Layout.alignment: Qt.AlignRight
            ToolTip.text: "Удалить график"
            ToolTip.visible: hovered
            padding: 1
            flat: true
            background: Item {}
            onClicked: {
                // Уничтожаем этот плейсхолдер
                chartRoot.destroy();
            }
        }

        Canvas {
            id: lineChartCanvas
            Layout.fillWidth: true
            Layout.fillHeight: true // Изменено с Layout.preferredHeight для максимального использования пространства
            Layout.minimumHeight: 150 // Гарантированная минимальная высота
            antialiasing: true

            // Добавляем MouseArea для обработки зума и пана
            MouseArea {
                id: chartMouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                
                onPressed: function(mouse) {
                    if (xAxisSelector.currentText !== "t, с") {
                        mouse.accepted = false; // Не перехватываем для других типов графиков
                        return;
                    }
                    
                    chartRoot.autoScrollToEnd = false; // Отключаем автоследование
                    chartRoot.isPanning = true;
                    chartRoot.lastPanPos = Qt.point(mouse.x, mouse.y);
                    // console.log("Mouse press: disabled auto-scroll, started panning");
                }
                
                onPositionChanged: function(mouse) {
                    if (!chartRoot.isPanning || xAxisSelector.currentText !== "t, с") {
                        return;
                    }
                    
                    // Рассчитываем смещение в пикселях
                    var deltaX = chartRoot.lastPanPos.x - mouse.x;
                    chartRoot.lastPanPos = Qt.point(mouse.x, mouse.y);
                    
                    // Преобразуем смещение пикселей в единицы данных по оси X
                    var chartWidth = lineChartCanvas.width - 80; // Приблизительно учитываем padding
                    var xRange = chartRoot.viewPortMaxX - chartRoot.viewPortMinX;
                    var deltaInDataUnits = (deltaX / chartWidth) * xRange;
                    
                    // Обновляем viewPort с учетом смещения
                    var oldMinX = chartRoot.viewPortMinX;
                    var oldMaxX = chartRoot.viewPortMaxX;
                    var newMinX = chartRoot.viewPortMinX + deltaInDataUnits;
                    var newMaxX = chartRoot.viewPortMaxX + deltaInDataUnits;
                    
                    // Ограничиваем панорамирование диапазоном данных
                    if (newMinX < chartRoot.fullHistoryMinTime) {
                        var adjustment = chartRoot.fullHistoryMinTime - newMinX;
                        newMinX += adjustment;
                        newMaxX += adjustment;
                    }
                    
                    if (newMaxX > chartRoot.fullHistoryMaxTime) {
                        var adjustment = newMaxX - chartRoot.fullHistoryMaxTime;
                        newMinX -= adjustment;
                        newMaxX -= adjustment;
                    }
                    
                    chartRoot.viewPortMinX = newMinX;
                    chartRoot.viewPortMaxX = newMaxX;
                    // console.log("Panning: viewport shifted from [" + oldMinX.toFixed(2) + "," + oldMaxX.toFixed(2) + 
                    //           "] to [" + chartRoot.viewPortMinX.toFixed(2) + "," + chartRoot.viewPortMaxX.toFixed(2) + 
                    //           "], by dx=" + deltaX.toFixed(2));
                    
                    updateChartDataAndPaint();
                }
                
                onReleased: function(mouse) {
                    if (xAxisSelector.currentText !== "t, с") {
                        return;
                    }
                    
                    chartRoot.isPanning = false;
                }
                
                onWheel: function(wheel) {
                    if (xAxisSelector.currentText !== "t, с") {
                        wheel.accepted = false; // Не перехватываем для других типов графиков
                        return;
                    }
                    
                    // Отключаем автоследование при любом взаимодействии
                    chartRoot.autoScrollToEnd = false;
                    
                    // Определяем фактор масштабирования (delta < 0 - увеличить, delta > 0 - уменьшить)
                    var zoomFactor = wheel.angleDelta.y < 0 ? 1.2 : 0.8;
                    
                    // Рассчитываем положение мыши в координатах данных
                    var chartWidth = lineChartCanvas.width - 80; // Приблизительно учитываем padding
                    var leftPadding = 60; // Приблизительно левый отступ
                    var mouseXRatio = (wheel.x - leftPadding) / chartWidth;
                    
                    // Если мышь за пределами графика, центрируем зум
                    if (mouseXRatio < 0 || mouseXRatio > 1) {
                        mouseXRatio = 0.5;
                    }
                    
                    var mouseDataX = chartRoot.viewPortMinX + mouseXRatio * (chartRoot.viewPortMaxX - chartRoot.viewPortMinX);
                    
                    // Вычисляем новую ширину диапазона
                    var newRangeX = (chartRoot.viewPortMaxX - chartRoot.viewPortMinX) * zoomFactor;
                    
                    // Ограничиваем диапазон (от 1 секунды до полной длительности истории)
                    var maxRange = Math.max(chartRoot.fullHistoryMaxTime - chartRoot.fullHistoryMinTime, 30);
                    var minRange = 1.0; // Минимум 1 секунда
                    
                    if (newRangeX > maxRange) newRangeX = maxRange;
                    if (newRangeX < minRange) newRangeX = minRange;
                    
                    // Рассчитываем новые границы, центрируя относительно позиции мыши
                    var newMinX = mouseDataX - mouseXRatio * newRangeX;
                    var newMaxX = newMinX + newRangeX;
                    
                    // Проверяем и корректируем границы
                    if (newMinX < chartRoot.fullHistoryMinTime) {
                        newMinX = chartRoot.fullHistoryMinTime;
                        newMaxX = newMinX + newRangeX;
                    }
                    
                    if (newMaxX > chartRoot.fullHistoryMaxTime) {
                        newMaxX = chartRoot.fullHistoryMaxTime;
                        newMinX = newMaxX - newRangeX;
                        
                        // Если минX выходит за левую границу после корректировки
                        if (newMinX < chartRoot.fullHistoryMinTime) {
                            newMinX = chartRoot.fullHistoryMinTime;
                        }
                    }
                    
                    // Применяем новые границы
                    chartRoot.viewPortMinX = newMinX;
                    chartRoot.viewPortMaxX = newMaxX;
                    
                    updateChartDataAndPaint();
                }
            }

            onPaint: {
                if (!visible || width <= 0 || height <= 0) return;
                var ctx = getContext("2d");
                if (!ctx) return;

                // --- НОВЫЙ БЛОК ДЛЯ ОБРАБОТКИ СМЕНЫ ТЕМЫ ---
                if (chartRoot.themeJustChanged) {
                    console.log("Theme Change - Pass 1: Requesting offscreen repaints and scheduling Pass 2.");
                    // Запрашиваем перерисовку скрытых холстов с новыми цветами
                    if (backgroundFeaturesCanvas.available) backgroundFeaturesCanvas.requestPaint();
                    if (dataLineOffscreenCanvas.available) dataLineOffscreenCanvas.requestPaint();
                    
                    chartRoot.themeJustChanged = false; // Сбрасываем флаг
                    // Планируем второй проход, который "проявит" уже готовые скрытые холсты
                    Qt.callLater(lineChartCanvas.requestPaint);
                    return; // Важно: прерываем текущую отрисовку
                }
                // --- КОНЕЦ НОВОГО БЛОКА ---

                // Обычная отрисовка или второй проход после смены темы
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = chartRoot.isDarkTheme ? "#333333" : "white";
                ctx.fillRect(0, 0, width, height);

                var padding = { top: 10, right: 10, bottom: 35, left: 45 };
                var chartWidth = width - padding.left - padding.right;
                var chartHeight = height - padding.top - padding.bottom;

                if (chartWidth <= 0 || chartHeight <= 0) {
                    ctx.fillStyle = chartRoot.isDarkTheme ? "#AAAAAA" : "#555555";
                    ctx.font = "10px sans-serif";
                    ctx.textAlign = "center";
                    ctx.fillText("Область графика слишком мала", width / 2, height / 2);
                    return;
                }

                var data = chartRoot.chartData;
                if (!data || data.length < 1) {
                    ctx.fillStyle = "#555"; // Используем один цвет, т.к. фон самого холста уже задан темой
                    ctx.font = "10px sans-serif";
                    ctx.textAlign = "center";
                    if (chartRoot.currentChartType === "poincare") {
                        ctx.fillText("Нет данных для карты Пуанкаре (запустите симуляцию)", width / 2, height / 2);
                    } else {
                        ctx.fillText("Нет данных для отображения", width / 2, height / 2);
                    }
                    return;
                }
                
                var minX, maxX, minY, maxY;
                
                if (chartRoot.currentChartType === "poincare") {
                    // Для режима Пуанкаре находим границы по всем сериям
                    var hasFoundAnyPoint = false;
                    
                    // Инициализация граничных значений
                    for (var seriesIndex = 0; seriesIndex < chartRoot.poincareSeriesList.length; seriesIndex++) {
                        var series = chartRoot.poincareSeriesList[seriesIndex];
                        if (series.points.length > 0) {
                            if (!hasFoundAnyPoint) {
                                minX = series.points[0].x;
                                maxX = series.points[0].x;
                                minY = series.points[0].y;
                                maxY = series.points[0].y;
                                hasFoundAnyPoint = true;
                            }
                            
                            // Поиск min/max в серии
                            for (var i = 0; i < series.points.length; ++i) {
                                if (series.points[i].x < minX) minX = series.points[i].x;
                                if (series.points[i].x > maxX) maxX = series.points[i].x;
                                if (series.points[i].y < minY) minY = series.points[i].y;
                                if (series.points[i].y > maxY) maxY = series.points[i].y;
                            }
                        }
                    }
                    
                    // Если нет точек, задаем дефолтный диапазон
                    if (!hasFoundAnyPoint) {
                        minX = -1;
                        maxX = 1;
                        minY = -1;
                        maxY = 1;
                    }
                } else {
                    // Обычный режим графика
                    if (xAxisSelector.currentText === "t, с") {
                        // Для временных рядов используем значения из viewPort
                        minX = chartRoot.viewPortMinX;
                        maxX = chartRoot.viewPortMaxX;
                        // console.log("onPaint: Using time series viewport: X=[" + minX.toFixed(2) + "," + maxX.toFixed(2) + "]");
                        
                        // minY и maxY рассчитываем по видимым данным
                        if (data.length > 0) {
                            minY = data[0].y;
                            maxY = minY;
                            
                            for (var i = 0; i < data.length; ++i) {
                                if (data[i].y < minY) minY = data[i].y;
                                if (data[i].y > maxY) maxY = data[i].y;
                            }
                        } else {
                            minY = -1;
                            maxY = 1;
                        }
                    } else {
                        // Для фазовых портретов рассчитываем все границы по данным
                        if (data.length > 0) {
                            minX = data[0].x;
                            maxX = minX;
                            minY = data[0].y;
                            maxY = minY;
                            
                            if (data.length > 1) {
                                for (var i = 1; i < data.length; ++i) {
                                    if (data[i].x < minX) minX = data[i].x;
                                    if (data[i].x > maxX) maxX = data[i].x;
                                    if (data[i].y < minY) minY = data[i].y;
                                    if (data[i].y > maxY) maxY = data[i].y;
                                }
                            } else {
                                minX = data[0].x - 0.5;
                                maxX = data[0].x + 0.5;
                                minY = data[0].y - 0.5;
                                maxY = data[0].y + 0.5;
                            }
                        } else {
                            // Если нет точек вообще
                            minX = -1;
                            maxX = 1;
                            minY = -1;
                            maxY = 1;
                        }
                    }
                }
                
                if (minX === maxX) { minX -= 0.5; maxX += 0.5; }
                
                // Сохраняем исходные диапазоны данных (minX_data, maxX_data, minY_data, maxY_data)
                // minX, maxY, minY, maxY на этом этапе содержат значения из viewPort (для времени)
                // или вычисленные по всем точкам (для фазовых портретов/Пуанкаре)
                var xDataMin = minX;
                var xDataMax = maxX;
                var yDataMin = minY;
                var yDataMax = maxY;

                var xInitialDataRange = xDataMax - xDataMin;
                if (xInitialDataRange === 0) xInitialDataRange = 1; 
                
                var yInitialDataRange = yDataMax - yDataMin;
                if (yInitialDataRange === 0) { yDataMin -= 0.5; yDataMax += 0.5; yInitialDataRange = 1; }

                // Устанавливаем финальные minX, maxX, minY, maxY для масштабирования на Canvas
                if (xAxisSelector.currentText === "t, с") {
                    // Для всех временных рядов (как с автоследованием, так и с ручным зумом):
                    // Ось X: данные должны занимать всю ширину от padding.left до padding.left + chartWidth.
                    // Не добавляем внешние отступы к диапазону данных по X.
                    minX = xDataMin; // Начало диапазона данных = начало видимой области
                    maxX = xDataMax; // Конец диапазона данных = конец видимой области
                    
                    // Ось Y: по-прежнему добавляем отступы, чтобы избежать прилипания к границам
                    var yPaddingValue = yInitialDataRange * 0.15; 
                    minY = yDataMin - yPaddingValue;
                    maxY = yDataMax + yPaddingValue;

                } else {
                    // Стандартная логика отступов для фазовых портретов, карты Пуанкаре и других типов графиков
                    var xPaddingValue = xInitialDataRange * 0.15;
                    minX = xDataMin - xPaddingValue;
                    maxX = xDataMax + xPaddingValue;

                    var yPaddingValue = yInitialDataRange * 0.15;
                    minY = yDataMin - yPaddingValue;
                    maxY = yDataMax + yPaddingValue;
                }
                
                // Пересчитываем итоговые диапазоны для масштабирования
                var xRange = maxX - minX;
                if (xRange === 0) { minX -= 0.5; maxX += 0.5; xRange = 1; }

                var yRange = maxY - minY;
                if (yRange === 0) { minY -= 0.5; maxY += 0.5; yRange = 1; }

                // --- Логика обновления effectiveMin/Max ---
                chartRoot.effectiveMinX = minX;
                chartRoot.effectiveMaxX = maxX;
                chartRoot.effectiveMinY = minY;
                chartRoot.effectiveMaxY = maxY;
                chartRoot.prevCanvasWidth = width;
                chartRoot.prevCanvasHeight = height;
                
                // УДАЛЯЕМ ЛОГИКУ ОБНОВЛЕНИЯ СКРЫТЫХ ХОЛСТОВ:
                // var scaleActuallyChanged = (oldEffectiveMinX !== minX || 
                //                           oldEffectiveMaxX !== maxX || 
                //                           oldEffectiveMinY !== minY || 
                //                           oldEffectiveMaxY !== maxY);
                // var sizeActuallyChanged = (oldPrevCanvasWidth !== width || 
                //                          oldPrevCanvasHeight !== height);
                //
                // // ОБЫЧНАЯ перерисовка скрытых холстов (не из-за темы, а из-за масштаба/данных)
                // if (scaleActuallyChanged || sizeActuallyChanged) {
                //     if (backgroundFeaturesCanvas.available) backgroundFeaturesCanvas.requestPaint();
                // }
                // if (chartRoot.chartDataContentChanged || scaleActuallyChanged || sizeActuallyChanged) {
                //     if (dataLineOffscreenCanvas.available) dataLineOffscreenCanvas.requestPaint();
                // }
                
                // Просто собираем композицию из готовых холстов
                if (backgroundFeaturesCanvas.available) ctx.drawImage(backgroundFeaturesCanvas, 0, 0);
                if (dataLineOffscreenCanvas.available) ctx.drawImage(dataLineOffscreenCanvas, 0, 0);
                
                // chartRoot.chartDataContentChanged = false; // <-- УДАЛЯЕМ СБРОС ФЛАГА
                // console.log("--- lineChartCanvas.onPaint FINISHED ---");
            }
            
            // Скрытый холст для фоновых элементов (сетка, оси, метки)
            Canvas {
                id: backgroundFeaturesCanvas
                width: lineChartCanvas.width
                height: lineChartCanvas.height
                visible: false
                antialiasing: true
                
                Connections {
                    target: chartRoot
                    function onThemeChangedSignal() {
                        // console.log("backgroundFeaturesCanvas: Theme changed signal received. Requesting paint.");
                        backgroundFeaturesCanvas.requestPaint();
                    }
                }
                
                onPaint: {
                    // console.log("backgroundFeaturesCanvas onPaint. isDarkTheme:", chartRoot.isDarkTheme); // Для отладки
                    if (width <= 0 || height <= 0) return;
                    
                    var ctx = getContext("2d");
                    if (!ctx) return;
                    
                    ctx.clearRect(0, 0, width, height);
                    
                    var padding = { top: 10, right: 20, bottom: 40, left: 60 };
                    var chartWidth = width - padding.left - padding.right;
                    var chartHeight = height - padding.top - padding.bottom;
                    
                    if (chartWidth <= 0 || chartHeight <= 0) return;
                    
                    // Используем сохраненные эффективные значения масштабирования
                    var minX = chartRoot.effectiveMinX;
                    var maxX = chartRoot.effectiveMaxX;
                    var minY = chartRoot.effectiveMinY;
                    var maxY = chartRoot.effectiveMaxY;
                    
                    var xRange = maxX - minX;
                    var yRange = maxY - minY;
                    
                    function toCanvasX(dataX) {
                        return padding.left + ((dataX - minX) / xRange) * chartWidth;
                    }
                    
                    function toCanvasY(dataY) {
                        return padding.top + chartHeight - ((dataY - minY) / yRange) * chartHeight;
                    }
                    
                    // 1. Заливаем фон области графика белым
                    // ctx.fillStyle = "white"; // Старый код
                    ctx.fillStyle = chartRoot.isDarkTheme ? "#333333" : "white"; // Новый код
                    ctx.fillRect(padding.left, padding.top, chartWidth, chartHeight);
                    
                    // 2. Рисуем сетку
                    // ctx.strokeStyle = "#BBBBBB"; // Старый цвет
                    ctx.strokeStyle = chartRoot.isDarkTheme ? "#6E6E6E" : "#BBBBBB"; // Чуть светлее для темной темы
                    ctx.lineWidth = 0.5;
                    var numGridLinesX = 30; // Изменено с 20 до 30
                    var numGridLinesY = 24; // Изменено с 16 до 24

                    // Вертикальные линии сетки
                    for (var i = 0; i <= numGridLinesX; i++) {
                        var xPos = padding.left + (i / numGridLinesX) * chartWidth;
                        ctx.beginPath();
                        ctx.moveTo(xPos, padding.top);
                        ctx.lineTo(xPos, padding.top + chartHeight);
                        ctx.stroke();
                    }

                    // Горизонтальные линии сетки
                    for (var i = 0; i <= numGridLinesY; i++) {
                        var yPos = padding.top + (i / numGridLinesY) * chartHeight;
                        ctx.beginPath();
                        ctx.moveTo(padding.left, yPos);
                        ctx.lineTo(padding.left + chartWidth, yPos);
                        ctx.stroke();
                    }

                    // 3. Рисуем основные оси
                    // ctx.strokeStyle = "#333333";
                    ctx.strokeStyle = chartRoot.isDarkTheme ? "#A0A0A0" : "#333333";
                    ctx.lineWidth = 1;
                    // Ось Y
                    ctx.beginPath();
                    ctx.moveTo(padding.left, padding.top);
                    ctx.lineTo(padding.left, padding.top + chartHeight);
                    ctx.stroke();
                    // Ось X
                    ctx.beginPath();
                    ctx.moveTo(padding.left, padding.top + chartHeight);
                    ctx.lineTo(padding.left + chartWidth, padding.top + chartHeight);
                    ctx.stroke();

                    // 4. Рисуем нулевые линии (только для обычного режима, не для Пуанкаре)
                    if (chartRoot.currentChartType !== "poincare") {
                        // ctx.strokeStyle = "#000000"; // Старый цвет
                        ctx.strokeStyle = chartRoot.isDarkTheme ? "#E0E0E0" : "#000000";
                        ctx.lineWidth = 1.2;      // Увеличено с 1.0 до 1.2
                        
                        // Нулевая линия для Y
                        if (minY <= 0 && maxY >= 0) {
                            var yZero = toCanvasY(0);
                            ctx.beginPath();
                            ctx.moveTo(padding.left, yZero);
                            ctx.lineTo(padding.left + chartWidth, yZero);
                            ctx.stroke();
                        }
                        
                        // Нулевая линия для X
                        if (minX <= 0 && maxX >= 0) {
                            var xZero = toCanvasX(0);
                            ctx.beginPath();
                            ctx.moveTo(xZero, padding.top);
                            ctx.lineTo(xZero, padding.top + chartHeight);
                            ctx.stroke();
                        }
                    }
                    
                    // 5. Рисуем метки на осях (только для обычного режима, не для Пуанкаре)
                    ctx.fillStyle = chartRoot.isDarkTheme ? "#E0E0E0" : "#111111"; // Ярче для темной, чуть темнее для светлой
                    ctx.font = "bold 12px sans-serif"; // Увеличено с 11px до 12px и сделано жирным
                    
                    if (chartRoot.currentChartType !== "poincare") {
                        // Метки для Y
                        ctx.textAlign = "right";
                        ctx.textBaseline = "middle";
                        for (var i = 0; i <= numGridLinesY; i++) {
                            var valY = maxY - (i / numGridLinesY) * yRange;
                            var yPos = padding.top + (i / numGridLinesY) * chartHeight;
                            
                            // Проверка на нулевое значение для особого выделения
                            var isZeroY = Math.abs(valY) < 0.0001;
                            
                            var textHeightApproximation = 9; // Приблизительная высота для шрифта 9px
                            var skipThisYLabel = false;
                            
                            // Пропускаем метку, только если она очень близко к нижнему краю (оси X)
                            if (i === numGridLinesY && yPos > padding.top + chartHeight - textHeightApproximation / 1.5) {
                                skipThisYLabel = true;
                            }
                            
                            // Пропускаем метку, если она очень близко к верхнему краю графика
                            if (i === 0 && yPos < padding.top + textHeightApproximation / 1.5) {
                                skipThisYLabel = true;
                            }
                            
                            if (!skipThisYLabel) {
                                var decimals = 2; // Default precision
                                if (yAxisSelector.currentText.includes("°")) { // Changed from "град"
                                    decimals = 1; // Меньше десятичных знаков для углов
                                } else if (yAxisSelector.currentText.includes("энергия")) {
                                    decimals = 3; // Больше десятичных знаков для энергий
                                }
                                
                                // Общий цвет для меток
                                var labelColor = chartRoot.isDarkTheme ? "#DCDCDC" : "#333333"; // Светлее для темной темы
                                ctx.fillStyle = labelColor;
                                ctx.fillText(valY.toFixed(decimals), padding.left - 5, yPos);
                            }
                        }

                        // Метки для X
                        ctx.textAlign = "center";
                        ctx.textBaseline = "top";
                        var lastLabelEndX_regular = -Infinity; // Координата X правого края последней нарисованной метки
                        var labelSpacingBuffer_regular = 5;  // Минимальный отступ в пикселях между метками

                        for (var i = 0; i <= numGridLinesX; i++) {
                            var valX = minX + (i / numGridLinesX) * xRange;
                            var xPos = padding.left + (i / numGridLinesX) * chartWidth;
                            
                            var decimals = 1; // Default precision
                            if (xAxisSelector.currentText.includes("°")) { // Changed from "град"
                                decimals = 1;
                            } else if (xAxisSelector.currentText === "t, с") {
                                decimals = 1;
                            }
                            
                            var labelText = valX.toFixed(decimals);
                            var textWidth = ctx.measureText(labelText).width;
                            var labelStartX = xPos - textWidth / 2;
                            var labelEndX = xPos + textWidth / 2;
                            
                            var skipThisXLabel = false;
                            // Пропускаем метку, если она слишком близко к левому краю (оси Y)
                            if (i === 0 && xPos < padding.left + textWidth / 1.5) {
                                skipThisXLabel = true;
                            }
                            
                            // Пропускаем метку, если она слишком близко к правому краю графика
                            if (i === numGridLinesX && xPos > padding.left + chartWidth - textWidth / 1.5) {
                                skipThisXLabel = true;
                            }
                            
                            // Пропускаем метку, если она накладывается на предыдущую метку
                            if (labelStartX < lastLabelEndX_regular + labelSpacingBuffer_regular) {
                                skipThisXLabel = true;
                            }
                            
                            if (!skipThisXLabel) {
                                var labelColor = chartRoot.isDarkTheme ? "#DCDCDC" : "#333333"; // Светлее для темной темы
                                ctx.fillStyle = labelColor;
                                ctx.fillText(labelText, xPos, padding.top + chartHeight + 6);
                                lastLabelEndX_regular = labelEndX; // Обновляем позицию края последней нарисованной метки
                            }
                        }
                        
                        // Рисуем заголовки осей для обычного графика
                        var yLabel = yAxisSelector.currentText;
                        ctx.save();
                        ctx.textAlign = "center";
                        ctx.textBaseline = "bottom";
                        ctx.translate(padding.left - 45, padding.top + chartHeight / 2);
                        ctx.rotate(-Math.PI / 2);
                        ctx.fillStyle = chartRoot.isDarkTheme ? "#F0F0F0" : "#000000"; // Очень яркий для темной темы
                        ctx.font = "bold 13px sans-serif"; // Крупнее и жирнее
                        ctx.fillText(yLabel, 0, 0);
                        ctx.restore();

                        ctx.textAlign = "center";
                        ctx.textBaseline = "top";
                        ctx.fillStyle = chartRoot.isDarkTheme ? "#F0F0F0" : "#000000"; // Очень яркий для темной темы
                        ctx.font = "bold 13px sans-serif"; // Крупнее и жирнее
                        ctx.fillText(xAxisSelector.currentText, padding.left + chartWidth / 2, padding.top + chartHeight + 20);
                    } else {
                        // Обновляем заголовки осей для карты Пуанкаре
                        ctx.fillStyle = chartRoot.isDarkTheme ? "#F0F0F0" : "#000000"; // Очень яркий для темной темы
                        ctx.font = "bold 13px sans-serif"; // Крупнее и жирнее
                        
                        // Заголовок оси Y (omega2)
                        ctx.save();
                        ctx.textAlign = "center";
                        ctx.textBaseline = "bottom";
                        ctx.translate(padding.left - 35, padding.top + chartHeight / 2);
                        ctx.rotate(-Math.PI / 2);
                        ctx.fillText("ω₂, рад/с", 0, 0);
                        ctx.restore();
                        
                        // Заголовок оси X (theta2)
                        ctx.textAlign = "center";
                        ctx.textBaseline = "top";
                        ctx.fillText("θ₂, рад", padding.left + chartWidth / 2, padding.top + chartHeight + 20);
                        
                        // Добавляем числовые метки для карты Пуанкаре
                        
                        // Метки для оси Y (omega2)
                        ctx.fillStyle = chartRoot.isDarkTheme ? "#E0E0E0" : "#111111";
                        ctx.font = "bold 12px sans-serif";
                        ctx.textAlign = "right";
                        ctx.textBaseline = "middle";
                        
                        for (var i = 0; i <= numGridLinesY; i++) {
                            var valY = maxY - (i / numGridLinesY) * yRange;
                            var yPos = padding.top + (i / numGridLinesY) * chartHeight;
                            
                            var textHeightApproximation = 9;
                            var skipThisYLabel = false;
                            
                            // Пропускаем метку, если она очень близко к нижнему краю
                            if (i === numGridLinesY && yPos > padding.top + chartHeight - textHeightApproximation / 1.5) {
                                skipThisYLabel = true;
                            }
                            
                            // Пропускаем метку, если она очень близко к верхнему краю графика
                            if (i === 0 && yPos < padding.top + textHeightApproximation / 1.5) {
                                skipThisYLabel = true;
                            }
                            
                            if (!skipThisYLabel) {
                                var labelColor = chartRoot.isDarkTheme ? "#DCDCDC" : "#333333";
                                ctx.fillStyle = labelColor;
                                ctx.fillText(valY.toFixed(2), padding.left - 5, yPos);
                            }
                        }
                        
                        // Метки для оси X (theta2)
                        ctx.textAlign = "center";
                        ctx.textBaseline = "top";
                        var lastLabelEndX = -Infinity; // Координата X правого края последней нарисованной метки
                        var labelSpacingBuffer = 5;  // Минимальный отступ в пикселях между метками

                        // Используем оригинальное количество линий сетки для расчета потенциальных позиций меток
                        var numPotentialLabelsX = 20; // или 30, как было для других графиков, или ваше предпочтительное значение

                        for (var i = 0; i <= numPotentialLabelsX; i++) {
                            var valX = minX + (i / numPotentialLabelsX) * xRange;
                            var xPos = padding.left + (i / numPotentialLabelsX) * chartWidth;

                            var decimals = 2; // Для карты Пуанкаре (радианы)
                            var labelText = valX.toFixed(decimals);
                            var textWidth = ctx.measureText(labelText).width;
                            var labelStartX = xPos - textWidth / 2;
                            var labelEndX = xPos + textWidth / 2;

                            // Пропускаем метку, если она слишком близко к левому краю (оси Y),
                            // или если она слишком близко к правому краю графика,
                            // ИЛИ если она накладывается на предыдущую метку
                            var skipThisXLabel = false;
                            if (i === 0 && xPos < padding.left + textWidth / 1.5) { // Слишком близко к оси Y
                                skipThisXLabel = true;
                            }
                            if (i === numPotentialLabelsX && xPos > padding.left + chartWidth - textWidth / 1.5) { // Слишком близко к правому краю
                                skipThisXLabel = true;
                            }
                            if (labelStartX < lastLabelEndX + labelSpacingBuffer) { // Накладывается на предыдущую
                                skipThisXLabel = true;
                            }

                            if (!skipThisXLabel) {
                                var labelColor = chartRoot.isDarkTheme ? "#DCDCDC" : "#333333";
                                ctx.fillStyle = labelColor;
                                ctx.fillText(labelText, xPos, padding.top + chartHeight + 6);
                                lastLabelEndX = labelEndX; // Обновляем позицию края последней нарисованной метки
                            }
                        }
                    }
                }
            }
            
            // Скрытый холст для линий данных
            Canvas {
                id: dataLineOffscreenCanvas
                width: lineChartCanvas.width
                height: lineChartCanvas.height
                visible: false
                antialiasing: true
                
                Connections {
                    target: chartRoot
                    function onThemeChangedSignal() {
                        // console.log("dataLineOffscreenCanvas: Theme changed signal received. Requesting paint.");
                        dataLineOffscreenCanvas.requestPaint();
                    }
                }
                
                onPaint: {
                    // console.log("dataLineOffscreenCanvas onPaint. isDarkTheme:", chartRoot.isDarkTheme); // Для отладки
                    if (width <= 0 || height <= 0) return;
                    
                    var ctx = getContext("2d");
                    if (!ctx) return;
                    
                    ctx.clearRect(0, 0, width, height);
                    
                    var padding = { top: 10, right: 20, bottom: 40, left: 60 };
                    var chartWidth = width - padding.left - padding.right;
                    var chartHeight = height - padding.top - padding.bottom;
                    
                    if (chartWidth <= 0 || chartHeight <= 0) return;
                    
                    // Используем сохраненные эффективные значения масштабирования
                    var minX = chartRoot.effectiveMinX;
                    var maxX = chartRoot.effectiveMaxX;
                    var minY = chartRoot.effectiveMinY;
                    var maxY = chartRoot.effectiveMaxY;
                    
                    var xRange = maxX - minX;
                    var yRange = maxY - minY;
                    
                    function toCanvasX(dataX) {
                        return padding.left + ((dataX - minX) / xRange) * chartWidth;
                    }
                    
                    function toCanvasY(dataY) {
                        return padding.top + chartHeight - ((dataY - minY) / yRange) * chartHeight;
                    }
                    
                    var data = chartRoot.chartData;
                    if (!data || data.length < 1) return;
                    
                    if (chartRoot.currentChartType === "poincare") {
                        // Отрисовка точек Карты Пуанкаре из всех серий
                        var pointRadius = chartRoot.poincarePointRadius; // Используем динамический радиус
                        
                        // Рисуем все сохраненные серии
                        for (var seriesIndex = 0; seriesIndex < chartRoot.poincareSeriesList.length; seriesIndex++) {
                            var series = chartRoot.poincareSeriesList[seriesIndex];
                            ctx.fillStyle = series.color; // Используем цвет из серии
                            
                            // Рисуем все точки серии
                            for (var i = 0; i < series.points.length; ++i) {
                                var canvasX = toCanvasX(series.points[i].x); // .x это theta2
                                var canvasY = toCanvasY(series.points[i].y); // .y это omega2

                                // Рисуем кружок
                                ctx.beginPath();
                                ctx.arc(canvasX, canvasY, pointRadius, 0, 2 * Math.PI);
                                ctx.fill();
                            }
                        }
                    } else {
                        // Обычная отрисовка линии графика
                        var lineColor = "black"; // Дефолтный цвет
                        switch (yAxisSelector.currentText) {
                            case "θ₁, °": // Changed from "град"
                            case "ω₁, рад/с":
                                lineColor = "red"; // Цвет первого боба
                                break;
                            case "θ₂, °": // Changed from "град"
                            case "ω₂, рад/с":
                                lineColor = "blue"; // Цвет второго боба
                                break;
                            case "T, Дж":
                                lineColor = "green";
                                break;
                            case "V, Дж":
                                lineColor = "purple";
                                break;
                            case "E, Дж":
                                lineColor = "black";
                                break;
                        }
                        // ctx.strokeStyle = lineColor; // Старый
                        ctx.strokeStyle = chartRoot.isDarkTheme ? (lineColor === "black" ? "white" : Qt.lighter(lineColor, 1.5)) : lineColor;
                        ctx.lineWidth = 1; // Тонкая линия для данных
                        ctx.beginPath();
                        ctx.moveTo(toCanvasX(data[0].x), toCanvasY(data[0].y));
                        for (var j = 1; j < data.length; ++j) {
                            ctx.lineTo(toCanvasX(data[j].x), toCanvasY(data[j].y));
                        }
                        ctx.stroke();
                    }
                }
            }
        }

        ColumnLayout {
            id: bottomControlBar
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight // Ensures the control bar only takes its natural height
            spacing: 5 // Уменьшено пространство между строками управления
            
            // For debugging layout issues - uncomment to visualize the bottomControlBar size
            // background: Rectangle { color: "orange"; opacity: 0.3 }
            
            // Первая строка: основные элементы управления
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                
                // Кнопки режимов
                RowLayout {
                    spacing: 10
                    
                    Button {
                        id: poincareMapModeToggleButton
                        text: ""
                        icon.source: chartRoot.currentChartType === "poincare" ? "qrc:/icons/charts.svg" : "qrc:/icons/dots.svg"
                        icon.width: 22
                        icon.height: 22
                        icon.color: chartRoot.isDarkTheme ? "#CCCCCC" : "#333333"
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        ToolTip.text: chartRoot.currentChartType === "poincare" ? "Показать графики" : "Показать карту Пуанкаре"
                        ToolTip.visible: hovered
                        padding: 1
                        flat: true
                        background: Item {}
                        onClicked: {
                            switchChartType(); // Используем централизованную функцию переключения
                            updateChartDataAndPaint(); // Добавляем прямой вызов для немедленной перерисовки
                        }
                    }
                    
                    // Кнопка для возврата к автоследованию для временных рядов
                    Button {
                        id: followDataButton
                        text: ""
                        icon.source: "qrc:/icons/eye.svg"
                        icon.width: 22
                        icon.height: 22
                        icon.color: chartRoot.isDarkTheme ? "#CCCCCC" : "#333333"
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        ToolTip.text: "К последним данным"
                        ToolTip.visible: hovered
                        padding: 1
                        flat: true
                        background: Item {}
                        visible: chartRoot.currentChartType !== "poincare" && 
                                 xAxisSelector.currentText === "t, с" && 
                                 !chartRoot.autoScrollToEnd
                        onClicked: {
                            chartRoot.autoScrollToEnd = true;
                            updateChartDataAndPaint();
                        }
                    }
                    
                    // Кнопка настроек оптимизации (RDP/limit)
                    Button {
                        id: chartSettingsButton
                        text: ""
                        icon.source: "qrc:/icons/settings2.svg"
                        icon.width: 22
                        icon.height: 22
                        icon.color: chartRoot.isDarkTheme ? "#CCCCCC" : "#333333"
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        ToolTip.text: "Настройки оптимизации"
                        ToolTip.visible: hovered
                        padding: 1
                        flat: true
                        background: Item {}
                        visible: xAxisSelector.currentText === "t, с" && chartRoot.currentChartType !== "poincare"
                        onClicked: {
                            optimizationSettingsPopup.open()
                        }
                    }
                    
                    // Выбор осей для графика (перемещено из второй RowLayout)
                    RowLayout {
                        id: axisSelectorsLayout
                        spacing: 5
                        opacity: chartRoot.currentChartType === "poincare" ? 0 : 1
                        enabled: chartRoot.currentChartType !== "poincare"
                        visible: chartRoot.currentChartType !== "poincare" // Явное управление видимостью, а не только прозрачностью
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                        
                        Label { 
                            text: "X:" 
                            Layout.alignment: Qt.AlignVCenter
                            color: chartRoot.isDarkTheme ? "white" : "black"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        
                        ComboBox {
                            id: xAxisSelector
                            Layout.preferredWidth: 90
                            Layout.preferredHeight: 24
                            model: ["t, с", "θ₁, °", "θ₂, °", "ω₁, рад/с", "ω₂, рад/с"] // Changed "град" to "°"
                            currentIndex: 0

                            // Custom indicator for the ComboBox
                            indicator: Canvas {
                                id: xAxisIndicator
                                x: parent.width - width - 6 // Position from right edge with small offset
                                y: parent.topPadding + (parent.availableHeight - height) / 2
                                width: 8  // Width of the triangle
                                height: 5 // Height of the triangle
                                
                                property color indicatorColor: chartRoot.isDarkTheme ? "#CCCCCC" : "#333333"

                                Connections {
                                    target: chartRoot
                                    function onIsDarkThemeChanged() {
                                        xAxisIndicator.requestPaint()
                                    }
                                }

                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    ctx.moveTo(0, 0);
                                    ctx.lineTo(width, 0);
                                    ctx.lineTo(width / 2, height);
                                    ctx.closePath();
                                    ctx.fillStyle = indicatorColor;
                                    ctx.fill();
                                }
                            }
                            
                            // Custom background for the ComboBox
                            background: Rectangle {
                                color: chartRoot.isDarkTheme ? "#444444" : "#DDDDDD"
                                radius: 3
                                border.color: chartRoot.isDarkTheme ? "#666666" : "#BBBBBB"
                                border.width: 1
                            }
                            
                            // Text content of the ComboBox
                            contentItem: RowLayout {
                                width: parent.width
                                height: parent.height
                                spacing: 0
                                
                                // Left spacer - equal distribution of space
                                Item { 
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                }
                                
                                Text {
                                    id: xAxisSelectorText
                                    text: xAxisSelector.currentText
                                    font.pixelSize: parent.parent.font.pixelSize
                                    font.bold: true
                                    color: chartRoot.isDarkTheme ? "#E0E0E0" : "#222222"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                // Right spacer - equal distribution of space
                                Item { 
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                }
                            }
                            
                            // Style for the popup with list items
                            popup: Popup {
                                y: xAxisSelector.height
                                width: xAxisSelector.width
                                implicitHeight: contentItem.implicitHeight
                                padding: 1
                                
                                contentItem: ListView {
                                    clip: true
                                    implicitHeight: contentHeight
                                    model: xAxisSelector.popup.visible ? xAxisSelector.delegateModel : null
                                    currentIndex: xAxisSelector.highlightedIndex
                                    
                                    ScrollIndicator.vertical: ScrollIndicator { }
                                }
                                
                                background: Rectangle {
                                    color: chartRoot.isDarkTheme ? "#444444" : "#FFFFFF"
                                    border.color: chartRoot.isDarkTheme ? "#666666" : "#BBBBBB"
                                    border.width: 1
                                    radius: 2
                                }
                            }
                            
                            // Custom styling for each dropdown item
                            delegate: ItemDelegate {
                                width: xAxisSelector.width
                                contentItem: Text {
                                    text: modelData
                                    color: chartRoot.isDarkTheme ? "#E0E0E0" : "#222222"
                                    // font: xAxisSelector.font
                                    font.pixelSize: xAxisSelector.font.pixelSize
                                    font.bold: true
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    width: parent.width
                                }
                                highlighted: xAxisSelector.highlightedIndex === index
                                
                                background: Rectangle {
                                    color: highlighted ? 
                                        (chartRoot.isDarkTheme ? "#666666" : "#DDDDDD") : 
                                        (chartRoot.isDarkTheme ? "#444444" : "#FFFFFF")
                                }
                            }
                            
                            onCurrentIndexChanged: {
                                updateChartDataAndPaint();
                            }
                        }
                        
                        Label { 
                            text: "Y:" 
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 10
                            color: chartRoot.isDarkTheme ? "white" : "black"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        
                        ComboBox {
                            id: yAxisSelector
                            Layout.preferredWidth: 90
                            Layout.preferredHeight: 24
                            model: ["θ₁, °", "θ₂, °", "ω₁, рад/с", "ω₂, рад/с",  // Changed "град" to "°"
                                   "T, Дж", "V, Дж", "E, Дж"]
                            currentIndex: 0
                            
                            // Custom indicator for the ComboBox
                            indicator: Canvas {
                                id: yAxisIndicator
                                x: parent.width - width - 6 // Position from right edge with small offset
                                y: parent.topPadding + (parent.availableHeight - height) / 2
                                width: 8  // Width of the triangle
                                height: 5 // Height of the triangle
                                
                                property color indicatorColor: chartRoot.isDarkTheme ? "#CCCCCC" : "#333333"

                                Connections {
                                    target: chartRoot
                                    function onIsDarkThemeChanged() {
                                        yAxisIndicator.requestPaint()
                                    }
                                }

                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    ctx.moveTo(0, 0);
                                    ctx.lineTo(width, 0);
                                    ctx.lineTo(width / 2, height);
                                    ctx.closePath();
                                    ctx.fillStyle = indicatorColor;
                                    ctx.fill();
                                }
                            }
                            
                            // Custom background for the ComboBox
                            background: Rectangle {
                                color: chartRoot.isDarkTheme ? "#444444" : "#DDDDDD"
                                radius: 3
                                border.color: chartRoot.isDarkTheme ? "#666666" : "#BBBBBB"
                                border.width: 1
                            }
                            
                            // Text content of the ComboBox
                            contentItem: RowLayout {
                                width: parent.width
                                height: parent.height
                                spacing: 0
                                
                                // Left spacer - equal distribution of space
                                Item { 
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                }
                                
                                Text {
                                    id: yAxisSelectorText
                                    text: yAxisSelector.currentText
                                    font.pixelSize: parent.parent.font.pixelSize
                                    font.bold: true
                                    color: chartRoot.isDarkTheme ? "#E0E0E0" : "#222222"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                // Right spacer - equal distribution of space
                                Item { 
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                }
                            }
                            
                            // Style for the popup with list items
                            popup: Popup {
                                y: yAxisSelector.height
                                width: yAxisSelector.width
                                implicitHeight: contentItem.implicitHeight
                                padding: 1
                                
                                contentItem: ListView {
                                    clip: true
                                    implicitHeight: contentHeight
                                    model: yAxisSelector.popup.visible ? yAxisSelector.delegateModel : null
                                    currentIndex: yAxisSelector.highlightedIndex
                                    
                                    ScrollIndicator.vertical: ScrollIndicator { }
                                }
                                
                                background: Rectangle {
                                    color: chartRoot.isDarkTheme ? "#444444" : "#FFFFFF"
                                    border.color: chartRoot.isDarkTheme ? "#666666" : "#BBBBBB"
                                    border.width: 1
                                    radius: 2
                                }
                            }
                            
                            // Custom styling for each dropdown item
                            delegate: ItemDelegate {
                                width: yAxisSelector.width
                                contentItem: Text {
                                    text: modelData
                                    color: chartRoot.isDarkTheme ? "#E0E0E0" : "#222222"
                                    // font: yAxisSelector.font
                                    font.pixelSize: yAxisSelector.font.pixelSize
                                    font.bold: true
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    width: parent.width
                                }
                                highlighted: yAxisSelector.highlightedIndex === index
                                
                                background: Rectangle {
                                    color: highlighted ? 
                                        (chartRoot.isDarkTheme ? "#666666" : "#DDDDDD") : 
                                        (chartRoot.isDarkTheme ? "#444444" : "#FFFFFF")
                                }
                            }
                            
                            onCurrentIndexChanged: {
                                updateChartDataAndPaint();
                            }
                        }
                    }
                }
                
                Item { Layout.fillWidth: true } // Распорка между группами
                
                // Элементы управления для карты Пуанкаре
                RowLayout {
                    id: poincareControlsLayout
                    opacity: chartRoot.currentChartType === "poincare" ? 1 : 0
                    enabled: chartRoot.currentChartType === "poincare"
                    visible: chartRoot.currentChartType === "poincare" // Явное управление видимостью, а не только прозрачностью
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    spacing: 10
                    
                    Row {
                        id: colorPalette
                        spacing: 5
                        Layout.alignment: Qt.AlignVCenter
                        
                        Repeater {
                            model: chartRoot.poincareColors
                            delegate: Rectangle {
                                width: 22; height: 22
                                color: modelData // modelData это текущий цвет из poincareColors
                                border.color: chartRoot.currentColorIndex === index ? (chartRoot.isDarkTheme ? "white" : "black") : "gray"
                                border.width: chartRoot.currentColorIndex === index ? 2 : 1
                                radius: 4

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        // 1. "Завершаем" текущую активную серию (она уже есть в poincareSeriesList)
                                        var activeSeriesIndex = chartRoot.poincareSeriesList.length - 1;
                                        if (activeSeriesIndex >= 0) {
                                            var latestPoints = mainWindow.pendulumObj.getPoincareMapPoints();
                                            // Обновляем точки последней (теперь уже "старой") активной серии
                                            // только если в C++ буфере есть новые точки
                                            if (latestPoints.length > 0) {
                                                chartRoot.poincareSeriesList[activeSeriesIndex].points = latestPoints;
                                                // console.log("Finalized series with color " + chartRoot.poincareSeriesList[activeSeriesIndex].color + 
                                                //             " and " + latestPoints.length + " points before switching color.");
                                            } else {
                                                // console.log("Preserved series with color " + chartRoot.poincareSeriesList[activeSeriesIndex].color + 
                                                //             " and " + chartRoot.poincareSeriesList[activeSeriesIndex].points.length + 
                                                //             " existing points before switching color (C++ buffer empty).");
                                            }
                                        }
                                        
                                        // 2. Устанавливаем НОВЫЙ текущий цвет
                                        chartRoot.currentColorIndex = index; // index из Repeater
                                        
                                        // 3. Очистить C++ буфер точек Пуанкаре
                                        mainWindow.pendulumObj.clearPoincareMapPoints();
                                        
                                        // 4. Добавить НОВУЮ АКТИВНУЮ серию с новым цветом и пустыми точками
                                        chartRoot.poincareSeriesList.push({
                                            "color": chartRoot.poincareColors[chartRoot.currentColorIndex],
                                            "points": []
                                        });
                                        
                                        // console.log("Started new Poincare series with color:", chartRoot.poincareColors[chartRoot.currentColorIndex]);
                                        updateChartDataAndPaint(); // Обновить отображение
                                    }
                                }
                            }
                        }
                    }
                    
                    Label {
                        text: "Размер точек:"
                        Layout.alignment: Qt.AlignVCenter
                        color: chartRoot.isDarkTheme ? "white" : "#333333"
                    }
                    
                    SpinBox {
                        id: pointSizeSpinBox
                        from: 5 // Представляет 0.5
                        to: 50   // Представляет 5.0
                        stepSize: 1 // Каждый шаг изменяет значение на 0.1
                        value: Math.round(chartRoot.poincarePointRadius * 10) // Текущее значение, умноженное на 10
                        Layout.preferredWidth: 80
                        
                        // Отображение фактического значения (с десятичной точкой)
                        textFromValue: function(value) {
                            return (value / 10.0).toFixed(1);
                        }
                        
                        valueFromText: function(text) {
                            return Math.round(parseFloat(text) * 10);
                        }
                        
                        onValueChanged: {
                            chartRoot.poincarePointRadius = value / 10.0;
                            lineChartCanvas.requestPaint(); // Перерисовать с новым размером точек
                        }
                    }
                    
                    Button {
                        id: clearPoincareMapButton
                        text: ""
                        icon.source: "qrc:/icons/wastebasket.svg"
                        icon.width: 22
                        icon.height: 22
                        icon.color: chartRoot.isDarkTheme ? "#CCCCCC" : "#333333"
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        ToolTip.text: "Очистить карту Пуанкаре"
                        ToolTip.visible: hovered
                        padding: 1
                        flat: true
                        background: Item {}
                        onClicked: {
                            chartRoot.poincareSeriesList = []; // Очищаем список серий в QML
                            chartRoot.currentColorIndex = 0;   // Сбрасываем индекс цвета
                            if (mainWindow.pendulumObj) {
                                mainWindow.pendulumObj.clearPoincareMapPoints(); // Очищаем буфер точек в C++
                            }
                            // Создаем первую "пустую" активную серию для новых точек
                            if (chartRoot.poincareSeriesList.length === 0 && mainWindow.pendulumObj) {
                                chartRoot.poincareSeriesList.push({
                                    "color": chartRoot.poincareColors[chartRoot.currentColorIndex],
                                    "points": []
                                });
                            }
                            lineChartCanvas.requestPaint(); // Перерисовать пустую карту
                            // console.log("Poincare map cleared.");
                        }
                    }
                }
                
                Item { Layout.fillWidth: true } // Распорка между группами
                
                // Экспортные кнопки (всегда видимы)
                RowLayout {
                    spacing: 5
                    
                    Button {
                        id: exportDataButton
                        text: ""
                        icon.source: "qrc:/icons/download.svg"
                        icon.width: 22
                        icon.height: 22
                        icon.color: chartRoot.isDarkTheme ? "#CCCCCC" : "#333333"
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        ToolTip.text: "Экспорт графика в PNG"
                        ToolTip.visible: hovered
                        padding: 1
                        flat: true
                        background: Item {}
                        onClicked: pngSaveDialog.open()
                    }
                }
            }
        }
    }
    
    // Popup для настроек оптимизации графика
    Popup {
        id: optimizationSettingsPopup
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: rdpLimitGridLayout.implicitWidth + 20
        height: Math.max(rdpLimitGridLayout.implicitHeight + 20, 120)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            color: chartRoot.isDarkTheme ? "#333333" : "white"
            border.color: chartRoot.isDarkTheme ? "#555555" : "#DCDCDC"
            border.width: 1
            radius: 4
        }
        
        // Копия GridLayout с настройками RDP/лимита
        GridLayout {
            id: rdpLimitGridLayout
            anchors.centerIn: parent
            columns: 2
            columnSpacing: 5
            rowSpacing: 2
            
            CheckBox {
                id: rdpEnabledCheckBox
                text: "Упрощать (RDP)"
                checked: false
                Layout.columnSpan: 2
                onClicked: chartRoot.updateChartDataAndPaint()
                contentItem: Text {
                    text: rdpEnabledCheckBox.text
                    font: rdpEnabledCheckBox.font
                    color: chartRoot.isDarkTheme ? "white" : "#333333"
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: rdpEnabledCheckBox.indicator.width + rdpEnabledCheckBox.spacing
                }
            }
            
            Label {
                text: "Epsilon:"
                visible: rdpEnabledCheckBox.checked
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                color: chartRoot.isDarkTheme ? "white" : "#333333"
            }
            
            SpinBox {
                id: rdpEpsilonSpinBox
                visible: rdpEnabledCheckBox.checked
                from: 1    // 0.01 в реальности
                to: 1000   // 10.00 в реальности
                stepSize: 1
                value: 25  // 0.25 в реальности
                Layout.preferredWidth: 65
                
                textFromValue: function(value) {
                    return (value / 100.0).toFixed(2);
                }
                
                valueFromText: function(text) {
                    return Math.round(parseFloat(text) * 100);
                }
                
                onValueChanged: chartRoot.updateChartDataAndPaint()
            }
            
            CheckBox {
                id: limitPointsEnabledCheckBox
                text: "Ограничить точки"
                checked: true
                Layout.columnSpan: 2
                onClicked: chartRoot.updateChartDataAndPaint()
                contentItem: Text {
                    text: limitPointsEnabledCheckBox.text
                    font: limitPointsEnabledCheckBox.font
                    color: chartRoot.isDarkTheme ? "white" : "#333333"
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: limitPointsEnabledCheckBox.indicator.width + limitPointsEnabledCheckBox.spacing
                }
            }
            
            Label {
                text: "Макс. точек:"
                visible: limitPointsEnabledCheckBox.checked
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                color: chartRoot.isDarkTheme ? "white" : "#333333"
            }
            
            SpinBox {
                id: maxPointsSpinBox
                visible: limitPointsEnabledCheckBox.checked
                from: 100
                to: 50000
                stepSize: 500
                value: 10000
                Layout.preferredWidth: 70
                
                onValueChanged: chartRoot.updateChartDataAndPaint()
            }
        }
    }
    
    // Инициализация графика при создании компонента
    Component.onCompleted: {
        // Не вызываем updateChartDataAndPaint() здесь
        // Первоначальное обновление будет вызвано из Main.qml при необходимости
    }

    // Диалоги для экспорта
    FileDialog {
        id: pngSaveDialog
        title: "Сохранить изображение графика"
        //currentFolder: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
        fileMode: FileDialog.SaveFile
        nameFilters: ["PNG Images (*.png)"]
        
        onAccepted: {
            // Получаем путь и преобразуем его в локальный путь
            var selectedFile = pngSaveDialog.selectedFile;
            var localFilePath = "";
            
            // Преобразуем URL в локальный путь
            if (typeof selectedFile === 'object' && typeof selectedFile.toString === 'function') {
                // Если это объект URL, преобразуем его в строку
                var urlString = selectedFile.toString();
                
                // Удаляем "file:///" префикс
                if (urlString.startsWith("file:///")) {
                    localFilePath = urlString.substring(8); // Пропускаем "file:///"
                } else if (urlString.startsWith("file://")) {
                    localFilePath = urlString.substring(7); // Пропускаем "file://"
                } else {
                    localFilePath = urlString;
                }
            } else if (typeof selectedFile === 'string') {
                // Если это уже строка, проверяем, не URL ли это
                if (selectedFile.startsWith("file:///")) {
                    localFilePath = selectedFile.substring(8);
                } else if (selectedFile.startsWith("file://")) {
                    localFilePath = selectedFile.substring(7);
                } else {
                    localFilePath = selectedFile;
                }
            } else {
                console.error("QML: Unexpected type for selectedFile:", typeof selectedFile);
                return;
            }
            
            // console.log("QML: Saving chart as PNG to:", localFilePath);
            lineChartCanvas.grabToImage(function(result) {
                result.saveToFile(localFilePath);
                // console.log("QML: Chart image saved successfully to:", localFilePath);
            });
        }
    }
    
    // Функция для переключения между режимами отображения
    function switchChartType() {
        console.log("switchChartType called. Current type: " + currentChartType);
        
        if (currentChartType === "poincare") {
            // Переключаемся ИЗ режима Пуанкаре
            finalizeCurrentPoincareSeries();
            currentChartType = "time_series_or_phase";
        } else {
            // Переключаемся В режим Пуанкаре
            currentChartType = "poincare";
            
            // Создаем новую серию для точек Пуанкаре, если нужно
            if (poincareSeriesList.length === 0 || 
                (poincareSeriesList.length > 0 && mainWindow.pendulumObj)) {
                // Очищаем буфер точек в C++ перед созданием новой серии
                mainWindow.pendulumObj.clearPoincareMapPoints();
                
                // Добавляем новую серию с текущим цветом
                poincareSeriesList.push({
                    "color": poincareColors[currentColorIndex],
                    "points": []
                });
            }
        }
        
        // Явно обновляем состояние UI-элементов, зависящих от режима
        if (poincareControlsLayout) {
            poincareControlsLayout.opacity = currentChartType === "poincare" ? 1 : 0;
            poincareControlsLayout.enabled = currentChartType === "poincare";
            poincareControlsLayout.visible = currentChartType === "poincare";
        }
        
        if (axisSelectorsLayout) {
            axisSelectorsLayout.opacity = currentChartType === "poincare" ? 0 : 1;
            axisSelectorsLayout.enabled = currentChartType !== "poincare";
            axisSelectorsLayout.visible = currentChartType !== "poincare";
        }
        
        // Обновление происходит через onCurrentChartTypeChanged
    }

    // Этот обработчик синхронизирует все состояния при изменении типа графика
    onCurrentChartTypeChanged: {
        console.log("currentChartType changed to: " + currentChartType);
        
        // Принудительно обновляем все зависимые элементы, которые определяют видимость/активность
        // Это помогает избежать ситуаций, когда некоторые элементы не получают обновление
        if (currentChartType === "poincare") {
            // Для карты Пуанкаре скрываем селекторы осей
            if (xAxisSelectorText) xAxisSelectorText.text = xAxisSelector.customDisplayText;
            if (yAxisSelectorText) yAxisSelectorText.text = yAxisSelector.customDisplayText;
        } 
        
        // Делаем это через callLater для правильного порядка обновлений
        // Это критически важно - даёт возможность QML обработать изменение состояния
        // перед тем, как мы запросим перерисовку
        Qt.callLater(function() {
            // Полное обновление данных и визуального представления
            updateChartDataAndPaint();
            
            // Запрашиваем дополнительную перерисовку после обновления данных
            // Это помогает избежать проблем с "отскакиванием" отображения
            Qt.callLater(function() {
                if (lineChartCanvas && lineChartCanvas.available) {
                    lineChartCanvas.requestPaint();
                }
            });
        });
    }
}