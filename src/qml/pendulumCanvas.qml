import QtQuick 2.15

Canvas {
    id: pendulumCanvas
    anchors.fill: parent
    clip: false

    // --- Свойства для отрисовки ---
    property real massScaleFactorForRadius: 4.0
    property real traceLineWidth: 1.5
    property real maxRodMassForThickness: 10.0
    property real rodMassToThicknessExponent: 0.5
    property real minRodLineWidth: 2.0
    property real maxRodLineWidth: 10.0

    // --- Свойства для интерактивности ---
    property bool bob1Hovered: false
    property bool bob2Hovered: false
    property int draggingBob: 0

    // Properties for incremental trace drawing
    property var lastTrace1Point: null
    property var lastTrace2Point: null
    
    // ПУБЛИЧНАЯ ФУНКЦИЯ ОЧИСТКИ
    function clearAllTraces() {
        if(trace1OffscreenCanvas.available) trace1OffscreenCanvas.getContext("2d").clearRect(0,0,width,height);
        if(trace2OffscreenCanvas.available) trace2OffscreenCanvas.getContext("2d").clearRect(0,0,width,height);
        lastTrace1Point = null;
        lastTrace2Point = null;
    }
    
    function calculateVisualState(pendulumObject, canvasWidth, canvasHeight, massScaleFactor) {
        if (!pendulumObject) return null;
        var centerX = canvasWidth / 2;
        var centerY = canvasHeight / 2;
        var phys_l1 = Math.max(0.01, pendulumObject.l1);
        var phys_l2 = Math.max(0.01, pendulumObject.l2);
        var m1_mass = Math.max(0.01, pendulumObject.m1);
        var m2_mass = Math.max(0.01, pendulumObject.m2);
        var m1_rod = Math.max(0.01, pendulumObject.m1_rod);
        var m2_rod = Math.max(0.01, pendulumObject.m2_rod);
        var t1_abs_rad = pendulumObject.theta1;
        var t2_rel_rad = pendulumObject.theta2;
        var maxPhysicalReach = phys_l1 + phys_l2;
        var targetScreenReach = Math.min(canvasWidth, canvasHeight) * 0.42;
        var globalScaleFactor = targetScreenReach / Math.max(0.1, maxPhysicalReach);
        var l1_visual = Math.max(12, phys_l1 * globalScaleFactor);
        var l2_visual = Math.max(12, phys_l2 * globalScaleFactor);
        var r1_visual = Math.max(8, Math.min(Math.pow(m1_mass, 0.42) * massScaleFactor, 35));
        var r2_visual = Math.max(8, Math.min(Math.pow(m2_mass, 0.42) * massScaleFactor, 35));
        var x1_calc = centerX + l1_visual * Math.sin(t1_abs_rad);
        var y1_calc = centerY + l1_visual * Math.cos(t1_abs_rad);
        var t2_abs_for_drawing_rad = t1_abs_rad + t2_rel_rad;
        var x2_calc = x1_calc + l2_visual * Math.sin(t2_abs_for_drawing_rad);
        var y2_calc = y1_calc + l2_visual * Math.cos(t2_abs_for_drawing_rad);
        var rod1LineWidth = minRodLineWidth + (maxRodLineWidth - minRodLineWidth) * Math.pow(m1_rod / maxRodMassForThickness, rodMassToThicknessExponent);
        rod1LineWidth = Math.max(minRodLineWidth, Math.min(rod1LineWidth, maxRodLineWidth));
        var rod2LineWidth = minRodLineWidth + (maxRodLineWidth - minRodLineWidth) * Math.pow(m2_rod / maxRodMassForThickness, rodMassToThicknessExponent);
        rod2LineWidth = Math.max(minRodLineWidth, Math.min(rod2LineWidth, maxRodLineWidth));
        return { centerX, centerY, globalScaleFactor, l1_visual, l2_visual, x1: x1_calc, y1: y1_calc, r1: r1_visual, x2: x2_calc, y2: y2_calc, r2: r2_visual, rod1LineWidth, rod2LineWidth };
    }

    // Скрытые холсты для кеша
    Canvas { id: trace1OffscreenCanvas; width: parent.width; height: parent.height; visible: false }
    Canvas { id: trace2OffscreenCanvas; width: parent.width; height: parent.height; visible: false }

    Connections {
        target: pendulumObj
        function onStateChanged() { requestPaint(); }
        // onHistoryUpdated теперь вызывает инкрементальное обновление
        function onHistoryUpdated() { updateAndDrawNewTraceSegments(); }
    }

    // Главная функция отрисовки
    onPaint: {
        if (!available || !pendulumObj) return;
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        
        var visualState = calculateVisualState(pendulumObj, width, height, massScaleFactorForRadius);
        if (!visualState) return;

        if (mainWindow.show2DGridAndAxes) drawGrid(ctx, visualState);
        
        if (pendulumObj.showTrace1 && trace1OffscreenCanvas.available) ctx.drawImage(trace1OffscreenCanvas, 0, 0);
        if (pendulumObj.showTrace2 && trace2OffscreenCanvas.available) ctx.drawImage(trace2OffscreenCanvas, 0, 0);
        
        drawPendulum(ctx, visualState);
    }
    
    function drawGrid(ctx, visualState) {
        let centerX = visualState.centerX, centerY = visualState.centerY;
        let maxRadius = Math.min(width, height) * 0.42;
        
        ctx.strokeStyle = mainWindow.isDarkTheme ? "#6E6E6E" : "#CCCCCC"; 
        ctx.lineWidth = 0.5;
        
        [maxRadius * 0.25, maxRadius * 0.5, maxRadius * 0.75, maxRadius].forEach(r => { 
            ctx.beginPath(); 
            ctx.arc(centerX, centerY, r, 0, 2 * Math.PI); 
            ctx.stroke(); 
        });
        
        ctx.beginPath(); 
        ctx.arc(centerX, centerY, visualState.l1_visual, 0, 2 * Math.PI); 
        ctx.stroke();
        
        ctx.beginPath(); 
        ctx.arc(centerX, centerY, visualState.l1_visual + visualState.l2_visual, 0, 2 * Math.PI); 
        ctx.stroke();
        
        [-135, -90, -45, 0, 45, 90, 135, 180].forEach(deg => {
            let rad = deg * Math.PI / 180;
            ctx.beginPath(); 
            ctx.moveTo(centerX, centerY); 
            ctx.lineTo(centerX + maxRadius * Math.sin(rad), centerY + maxRadius * Math.cos(rad)); 
            ctx.stroke();
            
            ctx.fillStyle = mainWindow.isDarkTheme ? "#C0C0C0" : "#555555"; 
            ctx.font = "10px sans-serif";
            let xT = centerX + (maxRadius + 15) * Math.sin(rad), yT = centerY + (maxRadius + 15) * Math.cos(rad);
            ctx.textAlign = (deg === 90 || deg === -90) ? "center" : (xT < centerX ? "right" : "left");
            ctx.textBaseline = (deg === 0 || deg === 180) ? "middle" : (yT < centerY ? "bottom" : "top");
            ctx.fillText(deg + "°", xT, yT);
        });
        
        if (mainWindow.showBob2RelativeGrid) {
            let bob1x = visualState.x1, bob1y = visualState.y1, l2_vis = visualState.l2_visual;
            ctx.strokeStyle = "red"; 
            ctx.lineWidth = 0.5;
            ctx.beginPath(); 
            ctx.arc(bob1x, bob1y, l2_vis, 0, 2 * Math.PI); 
            ctx.stroke();
        }
    }
    
    function drawPendulum(ctx, visualState) {
        let centerX = visualState.centerX, centerY = visualState.centerY;
        let x1 = visualState.x1, y1 = visualState.y1, x2 = visualState.x2, y2 = visualState.y2;
        
        // Рисуем первый стержень
        ctx.strokeStyle = "#666666"; 
        ctx.lineWidth = visualState.rod1LineWidth; 
        ctx.lineCap = "round";
        ctx.beginPath(); 
        ctx.moveTo(centerX, centerY); 
        ctx.lineTo(x1, y1); 
        ctx.stroke();
        
        // Закрепление первого стержня
        ctx.fillStyle = "#000000"; 
        ctx.beginPath(); 
        ctx.arc(centerX, centerY, 4, 0, Math.PI * 2); 
        ctx.fill();
        
        // Рисуем второй стержень
        ctx.strokeStyle = "#888888"; 
        ctx.lineWidth = visualState.rod2LineWidth;
        ctx.beginPath(); 
        ctx.moveTo(x1, y1); 
        ctx.lineTo(x2, y2); 
        ctx.stroke();
        
        // Первый боб
        ctx.fillStyle = pendulumCanvas.draggingBob === 1 ? 
            "#880000" : (pendulumCanvas.bob1Hovered ? "#AA0000" : "#ff0000");
        ctx.beginPath(); 
        ctx.arc(x1, y1, visualState.r1, 0, Math.PI * 2); 
        ctx.fill();
        
        // Второй боб
        let bob2BaseColor = "#0000ff";
        
        // Создаем самовызывающуюся анонимную функцию для проверки.
        // Это самый надежный способ получить единственное значение (true/false).
        var isPoincareVisible = (function() {
            // Если мы не в режиме анализа или нет контейнера с графиками, то точно нет.
            if (!mainWindow.analysisModeActive || !chartsColumnLayout) {
                return false;
            }

            // Проходим по всем графикам
            for (var i = 0; i < chartsColumnLayout.children.length; ++i) {
                var chart = chartsColumnLayout.children[i];
                // Ищем ХОТЯ БЫ ОДИН видимый график с нужным типом
                if (chart && chart.visible && chart.currentChartType === "poincare") {
                    return true; // Нашли! Вспышка нужна.
                }
            }

            // Не нашли ни одного. Вспышка не нужна.
            return false;
        })();

        // Теперь главное условие — простое и понятное
        if (isPoincareVisible && pendulumObj && pendulumObj.bob2PoincareFlash) {
            // Если активен график Пуанкаре И есть сигнал от C++, рисуем вспышку
            ctx.fillStyle = "#FFFF00";
            ctx.strokeStyle = "black";
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.arc(x2, y2, visualState.r2, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
        } else {
            // Во всех остальных случаях - стандартная отрисовка
            if (pendulumCanvas.draggingBob === 2) {
                ctx.fillStyle = Qt.darker(bob2BaseColor, 1.5);
            } else if (pendulumCanvas.bob2Hovered) {
                ctx.fillStyle = Qt.darker(bob2BaseColor, 1.2);
            } else {
                ctx.fillStyle = bob2BaseColor;
            }
            
            ctx.beginPath();
            ctx.arc(x2, y2, visualState.r2, 0, Math.PI * 2);
            ctx.fill();
        }
    }

    // Функция ИНКРЕМЕНТНОЙ отрисовки
    function updateAndDrawNewTraceSegments() {
        if (!available || !pendulumObj) return;
        var visualState = calculateVisualState(pendulumObj, width, height, massScaleFactorForRadius);
        if (!visualState) return;

        // --- Траектория 1 ---
        if (pendulumObj.showTrace1) {
            let newPoints = pendulumObj.consumeNewTrace1Points();
            if (newPoints.length > 0) {
                let ctx = trace1OffscreenCanvas.getContext("2d");
                ctx.beginPath();
                // Соединяем со старой точкой, если она есть
                if(lastTrace1Point) {
                     ctx.moveTo(lastTrace1Point.x, lastTrace1Point.y);
                }
                // Рисуем новые сегменты
                for(var i=0; i<newPoints.length; ++i) {
                    let screenPoint = Qt.point(visualState.centerX + newPoints[i].x * visualState.globalScaleFactor, visualState.centerY + newPoints[i].y * visualState.globalScaleFactor);
                    ctx.lineTo(screenPoint.x, screenPoint.y);
                }
                ctx.strokeStyle = "rgba(255, 0, 0, 0.5)";
                ctx.lineWidth = traceLineWidth;
                ctx.stroke();
                // Обновляем последнюю точку
                lastTrace1Point = Qt.point(visualState.centerX + newPoints[newPoints.length-1].x * visualState.globalScaleFactor, visualState.centerY + newPoints[newPoints.length-1].y * visualState.globalScaleFactor);
            }
        }
        
        // --- Траектория 2 ---
        if (pendulumObj.showTrace2) {
            let newPoints = pendulumObj.consumeNewTrace2Points();
            if (newPoints.length > 0) {
                let ctx = trace2OffscreenCanvas.getContext("2d");
                ctx.beginPath();
                if(lastTrace2Point) {
                    ctx.moveTo(lastTrace2Point.x, lastTrace2Point.y);
                }
                for(var j=0; j<newPoints.length; ++j) {
                     let screenPoint = Qt.point(visualState.centerX + newPoints[j].x * visualState.globalScaleFactor, visualState.centerY + newPoints[j].y * visualState.globalScaleFactor);
                     ctx.lineTo(screenPoint.x, screenPoint.y);
                }
                ctx.strokeStyle = mainWindow.isDarkTheme ? "rgba(100, 100, 255, 0.7)" : "rgba(0, 0, 255, 0.5)";
                ctx.lineWidth = traceLineWidth;
                ctx.stroke();
                lastTrace2Point = Qt.point(visualState.centerX + newPoints[newPoints.length-1].x * visualState.globalScaleFactor, visualState.centerY + newPoints[newPoints.length-1].y * visualState.globalScaleFactor);
            }
        }
        requestPaint();
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: (mouse) => {
            if (!mainWindow.pendulumObj) return;
            if (pendulumCanvas.draggingBob > 0) {
                if (pendulumCanvas.draggingBob === 1) {
                    var centerX = pendulumCanvas.width / 2;
                    var centerY = pendulumCanvas.height / 2;
                    var newTheta1 = Math.atan2(mouse.x - centerX, mouse.y - centerY);
                    mainWindow.pendulumObj.theta1 = newTheta1;
                } else if (pendulumCanvas.draggingBob === 2) {
                    var visualState = pendulumCanvas.calculateVisualState(mainWindow.pendulumObj, pendulumCanvas.width, pendulumCanvas.height, pendulumCanvas.massScaleFactorForRadius);
                    if (!visualState) return;
                    var angleFromBob1_rad = Math.atan2(mouse.x - visualState.x1, mouse.y - visualState.y1);
                    var newRelativeTheta2_rad = angleFromBob1_rad - mainWindow.pendulumObj.theta1;
                    while (newRelativeTheta2_rad > Math.PI) newRelativeTheta2_rad -= 2 * Math.PI;
                    while (newRelativeTheta2_rad < -Math.PI) newRelativeTheta2_rad += 2 * Math.PI;
                    mainWindow.pendulumObj.theta2 = newRelativeTheta2_rad;
                }
            } else {
                var visualState = pendulumCanvas.calculateVisualState(mainWindow.pendulumObj, pendulumCanvas.width, pendulumCanvas.height, pendulumCanvas.massScaleFactorForRadius);
                if (!visualState) return;
                var distance1 = Math.sqrt(Math.pow(mouse.x - visualState.x1, 2) + Math.pow(mouse.y - visualState.y1, 2));
                pendulumCanvas.bob1Hovered = distance1 <= visualState.r1 * 1.5;
                var distance2 = Math.sqrt(Math.pow(mouse.x - visualState.x2, 2) + Math.pow(mouse.y - visualState.y2, 2));
                pendulumCanvas.bob2Hovered = distance2 <= visualState.r2 * 1.5;
            }
        }
        onPressed: (mouse) => {
            if (!mainWindow.pendulumObj) return;
            var visualState = pendulumCanvas.calculateVisualState(mainWindow.pendulumObj, pendulumCanvas.width, pendulumCanvas.height, pendulumCanvas.massScaleFactorForRadius);
            if (!visualState) return;
            var distance1 = Math.sqrt(Math.pow(mouse.x - visualState.x1, 2) + Math.pow(mouse.y - visualState.y1, 2));
            var distance2 = Math.sqrt(Math.pow(mouse.x - visualState.x2, 2) + Math.pow(mouse.y - visualState.y2, 2));
            if (distance1 <= visualState.r1 * 1.5 && distance2 <= visualState.r2 * 1.5) pendulumCanvas.draggingBob = (distance1 < distance2) ? 1 : 2;
            else if (distance1 <= visualState.r1 * 1.5) pendulumCanvas.draggingBob = 1;
            else if (distance2 <= visualState.r2 * 1.5) pendulumCanvas.draggingBob = 2;
            if (pendulumCanvas.draggingBob > 0) {
                if (simulationTimer.running) simulationTimer.stop();
                mainWindow.pendulumObj.clearTraces();
                pendulumCanvas.clearAllTraces(); // Clear trace visuals when starting drag
            }
        }
        onReleased: {
            if (pendulumCanvas.draggingBob > 0) {
                if (mainWindow.pendulumObj) mainWindow.pendulumObj.reset(mainWindow.pendulumObj.theta1, 0.0, mainWindow.pendulumObj.theta2, 0.0);
                pendulumCanvas.draggingBob = 0;
            }
        }
        onExited: {
            pendulumCanvas.bob1Hovered = false;
            pendulumCanvas.bob2Hovered = false;
        }
    }
} 