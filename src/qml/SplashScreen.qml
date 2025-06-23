import QtQuick
import QtQuick.Window

Window {
    id: splashWindow
    width: 780
    height: 224
    visible: true
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    
    // Signal to request transition to main application
    signal requestContinueToMainApplication()
    
    // Manual centering since we removed Qt.SplashScreen flag
    Component.onCompleted: {
        var screenGeometry = Screen.desktopAvailableHeight > 0 ? Qt.point(Screen.desktopAvailableWidth, Screen.desktopAvailableHeight) : Qt.point(Screen.width, Screen.height);
        splashWindow.x = (screenGeometry.x - splashWindow.width) / 2;
        splashWindow.y = (screenGeometry.y - splashWindow.height) / 2;
    }
    
    Rectangle {
        id: backgroundContainer
        anchors.fill: parent
        color: "#333333"
        radius: 10
        
        // 1. Фоновое изображение (перекрывает все окно)
        Image {
            id: backgroundImage
            anchors.fill: parent
            source: "qrc:/images/splash_background.png"
            fillMode: Image.PreserveAspectFit
            antialiasing: true
        }
        
        // 2. Контейнер для анимированного маятника (размещается поверх фона)
        Item {
            id: pendulumAnimationContainer
            width: 220
            height: 200
            anchors.top: parent.top
            anchors.topMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 25
            
            // Properties for pendulum visual appearance
            property color pendulumElementColor: "#E5E5E5" // Цвет текста/стержней/окантовки
            property color pendulumBackgroundColor: "#333333" // Цвет фона окна/заливки грузов
            property int borderWidth: 3 // Толщина окантовки и стержней
            
            // Pendulum physical properties
            property real rod1Length: 65
            property real rod2Length: 65
            property real bob1Radius: 8
            property real bob2Radius: 8
            
            // Pendulum animation properties
            property real theta1: 0  // First rod angle
            property real theta2: 0  // Second rod angle (relative to first rod)
            
            // Canvas for rendering the pendulum
            Canvas {
                id: pendulumCanvas
                anchors.fill: parent
                antialiasing: true
                
                // Calculate pendulum positions based on angles
                function calculatePendulumPositions() {
                    var baseHeight = 10; // Height of the base
                    var topMarginForBase = 10; // Top margin to ensure base is fully visible
                    
                    var x0 = width / 2;  // Horizontal center of suspension
                    var y0 = topMarginForBase + baseHeight; // Position where the first rod starts (below the base)
                    
                    // Calculate first rod end point (first bob)
                    var x1 = x0 + pendulumAnimationContainer.rod1Length * Math.sin(pendulumAnimationContainer.theta1);
                    var y1 = y0 + pendulumAnimationContainer.rod1Length * Math.cos(pendulumAnimationContainer.theta1);
                    
                    // Calculate second rod end point (second bob)
                    var t2_abs = pendulumAnimationContainer.theta1 + pendulumAnimationContainer.theta2;
                    var x2 = x1 + pendulumAnimationContainer.rod2Length * Math.sin(t2_abs);
                    var y2 = y1 + pendulumAnimationContainer.rod2Length * Math.cos(t2_abs);
                    
                    return {
                        x0: x0, y0: y0,  // Point where the first rod starts (center of base's bottom)
                        x1: x1, y1: y1,  // First bob
                        x2: x2, y2: y2,   // Second bob
                        baseDrawRectY: topMarginForBase // Y-coordinate for the top-left corner of the base
                    };
                }
                
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    
                    // Get pendulum positions
                    var positions = calculatePendulumPositions();
                    
                    // Define base dimensions
                    var baseWidth = 30;
                    var baseHeight = 10;
                    var baseX = positions.x0 - baseWidth / 2;
                    var baseY = positions.baseDrawRectY;
                    
                    // Draw rods first (from back to front)
                    ctx.strokeStyle = pendulumAnimationContainer.pendulumElementColor;
                    ctx.lineWidth = pendulumAnimationContainer.borderWidth;
                    
                    // Rod 1 - starts from the bottom center of the base
                    ctx.beginPath();
                    ctx.moveTo(positions.x0, positions.y0);
                    ctx.lineTo(positions.x1, positions.y1);
                    ctx.stroke();
                    
                    // Rod 2
                    ctx.beginPath();
                    ctx.moveTo(positions.x1, positions.y1);
                    ctx.lineTo(positions.x2, positions.y2);
                    ctx.stroke();
                    
                    // Draw the rectangular base
                    ctx.fillStyle = pendulumAnimationContainer.pendulumBackgroundColor;
                    ctx.strokeStyle = pendulumAnimationContainer.pendulumElementColor;
                    ctx.lineWidth = pendulumAnimationContainer.borderWidth;
                    ctx.beginPath();
                    ctx.rect(baseX, baseY, baseWidth, baseHeight);
                    ctx.fill();
                    ctx.stroke();
                    
                    // Draw bob 1
                    ctx.fillStyle = pendulumAnimationContainer.pendulumBackgroundColor;
                    ctx.strokeStyle = pendulumAnimationContainer.pendulumElementColor;
                    ctx.lineWidth = pendulumAnimationContainer.borderWidth;
                    ctx.beginPath();
                    ctx.arc(positions.x1, positions.y1, pendulumAnimationContainer.bob1Radius, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.stroke();
                    
                    // Draw bob 2
                    ctx.beginPath();
                    ctx.arc(positions.x2, positions.y2, pendulumAnimationContainer.bob2Radius, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.stroke();
                }
            }
            
            // Animating the first rod
            SequentialAnimation {
                running: true
                loops: Animation.Infinite
                
                NumberAnimation {
                    target: pendulumAnimationContainer
                    property: "theta1"
                    from: -0.35  // About -20 degrees
                    to: 0.35     // About 20 degrees
                    duration: 1800
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: pendulumAnimationContainer
                    property: "theta1"
                    from: 0.35   // About 20 degrees
                    to: -0.35    // About -20 degrees
                    duration: 1800
                    easing.type: Easing.InOutSine
                }
            }
            
            // Animating the second rod
            SequentialAnimation {
                running: true
                loops: Animation.Infinite
                
                NumberAnimation { 
                    target: pendulumAnimationContainer
                    property: "theta2"
                    from: 0.52   // About 30 degrees
                    to: -0.52    // About -30 degrees
                    duration: 1100
                    easing.type: Easing.InOutSine 
                }
                NumberAnimation { 
                    target: pendulumAnimationContainer
                    property: "theta2"
                    from: -0.52  // About -30 degrees
                    to: 0.52     // About 30 degrees
                    duration: 1100
                    easing.type: Easing.InOutSine 
                }
            }
            
            // Trigger canvas redraw when angles change
            onTheta1Changed: pendulumCanvas.requestPaint()
            onTheta2Changed: pendulumCanvas.requestPaint()
        }
        
        // 3. FocusScope и MouseArea для закрытия (поверх всего)
        Item {
            anchors.fill: parent
            focus: true
            
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Print || event.key === Qt.Key_ScrollLock || event.key === Qt.Key_Pause) {
                    event.accepted = false;
                    return;
                }
                splashWindow.requestContinueToMainApplication();
                event.accepted = true;
            }
            
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: {
                    splashWindow.requestContinueToMainApplication();
                }
            }
        }
    }
} 