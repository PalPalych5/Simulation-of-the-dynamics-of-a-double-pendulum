import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Canvas {
    id: pendulumCanvas
    anchors.fill: parent
    clip: false

    // --- Properties for C++ object reference ---
    property var pendulumObj: null // Will be set from parent
    property bool isDarkTheme: false // Will be set from parent
    property bool showGrid: false // Show grid and axes
    property bool showBob2RelativeGrid: false // Show relative grid for bob2
    property bool poincareFlashEnabled: false // Whether Poincaré section crossing should flash

    // --- Properties for drawing ---
    property real massScaleFactorForRadius: 4.0
    property real traceLineWidth: 1.5
    property real maxRodMassForThickness: 10.0
    property real rodMassToThicknessExponent: 0.5
    property real minRodLineWidth: 2.0
    property real maxRodLineWidth: 10.0
    
    // --- Properties for interactivity ---
    property bool bob1Hovered: false
    property bool bob2Hovered: false
    property int draggingBob: 0
    
    // Reference to the trace drawer
    property var traceDrawer: traceDrawerInstance

    // IncrementalTraceDrawer instance
    IncrementalTraceDrawer {
        id: traceDrawerInstance
        pendulumObj: pendulumCanvas.pendulumObj
        isDarkTheme: pendulumCanvas.isDarkTheme
        massScaleFactorForRadius: pendulumCanvas.massScaleFactorForRadius
        traceLineWidth: pendulumCanvas.traceLineWidth
        canvasWidth: pendulumCanvas.width
        canvasHeight: pendulumCanvas.height
    }

    // Public function to clear traces - can be called from outside
    function clearTraces() {
        if (traceDrawerInstance) {
            traceDrawerInstance.clearAllTraces();
        }
    }

    // Function to fully redraw offscreen traces
    function forceFullRedrawOfOffscreenTraces() {
        if (!available || !pendulumObj) return;
        
        // Clear caches
        var ctx1 = trace1OffscreenCanvas.getContext("2d");
        var ctx2 = trace2OffscreenCanvas.getContext("2d");
        
        ctx1.clearRect(0, 0, width, height);
        ctx2.clearRect(0, 0, width, height);
        
        lastScreenPointTrace1 = Qt.point(-1, -1);
        lastScreenPointTrace2 = Qt.point(-1, -1);
        drawnTrace1PointsCount = 0;
        drawnTrace2PointsCount = 0;
        
        // Force redraw all points from buffers
        updateAndDrawNewTraceSegments(true);
        
        // Request redraw of the main canvas
        requestPaint();
    }
    
    // Function for incremental drawing
    function updateAndDrawNewTraceSegments(forceRedrawAll) {
        if (!available || !pendulumObj || 
            !trace1OffscreenCanvas.available || 
            !trace2OffscreenCanvas.available) return;

        var visualState = calculateVisualState(pendulumObj, width, height, massScaleFactorForRadius);
        if (!visualState) return;

        var centerX = visualState.centerX;
        var centerY = visualState.centerY;
        var globalScaleFactor = visualState.globalScaleFactor;
        var maxDistance = (visualState.l1_visual + visualState.l2_visual) * 1.5; // Maximum threshold for breaks

        // --- Trace 1 ---
        if (pendulumObj.showTrace1) {
            let trace1Data = pendulumObj.getTrace1Points();
            if (trace1Data && trace1Data.length > 0) {
                let ctx1 = trace1OffscreenCanvas.getContext("2d");
                
                // Determine from which index to start drawing
                let startIdx = forceRedrawAll ? 0 : Math.max(0, drawnTrace1PointsCount);
                
                // If there are new points to draw
                if (startIdx < trace1Data.length) {
                    // For full redraw or if it's the first point
                    if (forceRedrawAll || startIdx == 0) {
                        lastScreenPointTrace1 = Qt.point(-1, -1);
                    }
                    
                    // Draw all new points
                    for (let i = startIdx; i < trace1Data.length; i++) {
                        let newScreenPoint = Qt.point(
                            centerX + trace1Data[i].x * globalScaleFactor,
                            centerY + trace1Data[i].y * globalScaleFactor
                        );
                        
                        // If there's already a previous point, draw a line
                        if (lastScreenPointTrace1.x !== -1) {
                            let dist = Math.sqrt(
                                Math.pow(newScreenPoint.x - lastScreenPointTrace1.x, 2) + 
                                Math.pow(newScreenPoint.y - lastScreenPointTrace1.y, 2)
                            );
                            
                            // Draw the line only if the distance is not too large (to prevent "tails")
                            if (dist < maxDistance) {
                                ctx1.beginPath();
                                ctx1.moveTo(lastScreenPointTrace1.x, lastScreenPointTrace1.y);
                                ctx1.lineTo(newScreenPoint.x, newScreenPoint.y);
                                ctx1.strokeStyle = "rgba(255, 0, 0, 0.5)";
                                ctx1.lineWidth = traceLineWidth;
                                ctx1.stroke();
                            }
                        }
                        
                        // Update the last drawn point
                        lastScreenPointTrace1 = newScreenPoint;
                    }
                    
                    // Update the counter of drawn points
                    drawnTrace1PointsCount = trace1Data.length;
                }
            }
        }
        
        // --- Trace 2 ---
        if (pendulumObj.showTrace2) {
            let trace2Data = pendulumObj.getTrace2Points();
            if (trace2Data && trace2Data.length > 0) {
                let ctx2 = trace2OffscreenCanvas.getContext("2d");
                
                // Determine from which index to start drawing
                let startIdx = forceRedrawAll ? 0 : Math.max(0, drawnTrace2PointsCount);
                
                // If there are new points to draw
                if (startIdx < trace2Data.length) {
                    // For full redraw or if it's the first point
                    if (forceRedrawAll || startIdx == 0) {
                        lastScreenPointTrace2 = Qt.point(-1, -1);
                    }
                    
                    // Draw all new points
                    for (let i = startIdx; i < trace2Data.length; i++) {
                        let newScreenPoint = Qt.point(
                            centerX + trace2Data[i].x * globalScaleFactor,
                            centerY + trace2Data[i].y * globalScaleFactor
                        );
                        
                        // If there's already a previous point, draw a line
                        if (lastScreenPointTrace2.x !== -1) {
                            let dist = Math.sqrt(
                                Math.pow(newScreenPoint.x - lastScreenPointTrace2.x, 2) + 
                                Math.pow(newScreenPoint.y - lastScreenPointTrace2.y, 2)
                            );
                            
                            // Draw the line only if the distance is not too large
                            if (dist < maxDistance) {
                                ctx2.beginPath();
                                ctx2.moveTo(lastScreenPointTrace2.x, lastScreenPointTrace2.y);
                                ctx2.lineTo(newScreenPoint.x, newScreenPoint.y);
                                ctx2.strokeStyle = isDarkTheme ? 
                                    "rgba(100, 100, 255, 0.7)" : "rgba(0, 0, 255, 0.5)";
                                ctx2.lineWidth = traceLineWidth;
                                ctx2.stroke();
                            }
                        }
                        
                        // Update the last drawn point
                        lastScreenPointTrace2 = newScreenPoint;
                    }
                    
                    // Update the counter of drawn points
                    drawnTrace2PointsCount = trace2Data.length;
                }
            }
        }

        // Request redraw of the main canvas to display updates
        requestPaint();
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

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: (mouse) => {
            if (!pendulumCanvas.pendulumObj) return;
            if (pendulumCanvas.draggingBob > 0) {
                if (pendulumCanvas.draggingBob === 1) {
                    var centerX = pendulumCanvas.width / 2;
                    var centerY = pendulumCanvas.height / 2;
                    var newTheta1 = Math.atan2(mouse.x - centerX, mouse.y - centerY);
                    pendulumCanvas.pendulumObj.theta1 = newTheta1;
                } else if (pendulumCanvas.draggingBob === 2) {
                    var visualState = pendulumCanvas.calculateVisualState(pendulumCanvas.pendulumObj, pendulumCanvas.width, pendulumCanvas.height, pendulumCanvas.massScaleFactorForRadius);
                    if (!visualState) return;
                    var angleFromBob1_rad = Math.atan2(mouse.x - visualState.x1, mouse.y - visualState.y1);
                    var newRelativeTheta2_rad = angleFromBob1_rad - pendulumCanvas.pendulumObj.theta1;
                    while (newRelativeTheta2_rad > Math.PI) newRelativeTheta2_rad -= 2 * Math.PI;
                    while (newRelativeTheta2_rad < -Math.PI) newRelativeTheta2_rad += 2 * Math.PI;
                    pendulumCanvas.pendulumObj.theta2 = newRelativeTheta2_rad;
                }
            } else {
                var visualState = pendulumCanvas.calculateVisualState(pendulumCanvas.pendulumObj, pendulumCanvas.width, pendulumCanvas.height, pendulumCanvas.massScaleFactorForRadius);
                if (!visualState) return;
                var distance1 = Math.sqrt(Math.pow(mouse.x - visualState.x1, 2) + Math.pow(mouse.y - visualState.y1, 2));
                pendulumCanvas.bob1Hovered = distance1 <= visualState.r1 * 1.5;
                var distance2 = Math.sqrt(Math.pow(mouse.x - visualState.x2, 2) + Math.pow(mouse.y - visualState.y2, 2));
                pendulumCanvas.bob2Hovered = distance2 <= visualState.r2 * 1.5;
            }
        }
        onPressed: (mouse) => {
            if (!pendulumCanvas.pendulumObj) return;
            var visualState = pendulumCanvas.calculateVisualState(pendulumCanvas.pendulumObj, pendulumCanvas.width, pendulumCanvas.height, pendulumCanvas.massScaleFactorForRadius);
            if (!visualState) return;
            var distance1 = Math.sqrt(Math.pow(mouse.x - visualState.x1, 2) + Math.pow(mouse.y - visualState.y1, 2));
            var distance2 = Math.sqrt(Math.pow(mouse.x - visualState.x2, 2) + Math.pow(mouse.y - visualState.y2, 2));
            
            if (distance1 <= visualState.r1 * 1.5 || distance2 <= visualState.r2 * 1.5) {
                // We are about to start dragging
                simulationTimer.stop();
                
                // Notify the C++ core that we are taking over
                pendulumCanvas.pendulumObj.setManualControl(true);
                
                // Determine which bob is being dragged
                if (distance1 <= visualState.r1 * 1.5 && distance2 <= visualState.r2 * 1.5) {
                    pendulumCanvas.draggingBob = (distance1 < distance2) ? 1 : 2;
                } else if (distance1 <= visualState.r1 * 1.5) {
                    pendulumCanvas.draggingBob = 1;
                } else if (distance2 <= visualState.r2 * 1.5) {
                    pendulumCanvas.draggingBob = 2;
                }
                
                if (pendulumCanvas.draggingBob > 0) {
                    pendulumCanvas.pendulumObj.clearTraces();
                    
                    // Clear traces in the trace drawer
                    if (traceDrawerInstance) {
                        traceDrawerInstance.clearAllTraces();
                    }
                } else {
                    // If we didn't grab any bob, reset the flag
                    pendulumCanvas.pendulumObj.setManualControl(false);
                }
            }
        }
        onReleased: {
            if (pendulumCanvas.draggingBob > 0) {
                // Return control to the simulation engine
                pendulumCanvas.pendulumObj.setManualControl(false);
                
                if (pendulumCanvas.pendulumObj) {
                    pendulumCanvas.pendulumObj.reset(
                        pendulumCanvas.pendulumObj.theta1, 0.0, 
                        pendulumCanvas.pendulumObj.theta2, 0.0
                    );
                }
                pendulumCanvas.draggingBob = 0;
            }
        }
        onExited: {
            pendulumCanvas.bob1Hovered = false;
            pendulumCanvas.bob2Hovered = false;
        }
        onPressAndHold: {
            if (pendulumCanvas.available) {
                pendulumCanvas.requestPaint();
            }
        }
    }

    Connections {
        target: pendulumObj
        function onStateChanged() { 
            if (pendulumCanvas.visible && pendulumCanvas.available) {
                pendulumCanvas.requestPaint();
            }
        }
        function onHistoryUpdated() {
            if (pendulumCanvas.visible && pendulumCanvas.available && traceDrawerInstance) {
                traceDrawerInstance.updateAndDrawNewTraceSegments(false);
                pendulumCanvas.requestPaint();
            }
        }
    }
    
    onPaint: {
        if (!available || !pendulumObj || width <= 0 || height <= 0) return;
        var ctx = getContext("2d");
        if (!ctx) return;
        ctx.clearRect(0, 0, width, height);
        var visualState = calculateVisualState(pendulumObj, width, height, massScaleFactorForRadius);
        if (!visualState) return;

        var centerX = visualState.centerX, centerY = visualState.centerY, globalScaleFactor = visualState.globalScaleFactor;

        // --- GRID DRAWING ---
        if (showGrid) {
            var maxRadius = Math.min(width, height) * 0.42;
            ctx.strokeStyle = isDarkTheme ? "#6E6E6E" : "#CCCCCC";
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
                
                var textRadius = maxRadius + 10;
                var xT = centerX + textRadius * Math.sin(radAngle);
                var yT = centerY + textRadius * Math.cos(radAngle);
                
                ctx.fillStyle = isDarkTheme ? "#C0C0C0" : "#555555";
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
        if (showBob2RelativeGrid) {
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
                
                var textRadius = l2_vis + 5;
                var xT = bob1x + textRadius * Math.sin(radAngle);
                var yT = bob1y + textRadius * Math.cos(radAngle);
                
                ctx.fillStyle = "#FF0000";
                ctx.font = "8px sans-serif";
                
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

        // --- DISPLAY CACHED TRAJECTORIES ---
        if (pendulumObj.showTrace1 && traceDrawerInstance) {
            let trace1Canvas = traceDrawerInstance.getTrace1Canvas();
            if (trace1Canvas && trace1Canvas.available) {
                ctx.drawImage(trace1Canvas, 0, 0);
            }
        }
        
        if (pendulumObj.showTrace2 && traceDrawerInstance) {
            let trace2Canvas = traceDrawerInstance.getTrace2Canvas();
            if (trace2Canvas && trace2Canvas.available) {
                ctx.drawImage(trace2Canvas, 0, 0);
            }
        }

        // --- DRAW RODS AND BOBS ---
        let x1 = visualState.x1, y1 = visualState.y1, x2 = visualState.x2, y2 = visualState.y2;
        ctx.strokeStyle = "#666666"; ctx.lineWidth = visualState.rod1LineWidth; ctx.lineCap = "round";
        ctx.beginPath(); ctx.moveTo(centerX, centerY); ctx.lineTo(x1, y1); ctx.stroke();
        ctx.fillStyle = "#000000"; ctx.beginPath(); ctx.arc(centerX, centerY, 4, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = "#888888"; ctx.lineWidth = visualState.rod2LineWidth;
        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
        ctx.fillStyle = pendulumCanvas.draggingBob === 1 ? "#880000" : (pendulumCanvas.bob1Hovered ? "#AA0000" : "#ff0000");
        ctx.beginPath(); ctx.arc(x1, y1, visualState.r1, 0, Math.PI * 2); ctx.fill();
        let bob2BaseColor = "#0000ff";

        // Use the poincareFlashEnabled property for flash detection
        if (poincareFlashEnabled && pendulumObj && pendulumObj.bob2PoincareFlash) {
            // If Poincare flash is enabled AND there's a signal from C++, draw the flash
            ctx.fillStyle = "#FFFF00";
            ctx.strokeStyle = "black";
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.arc(x2, y2, visualState.r2, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
        } else {
            // In all other cases - standard drawing
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
} 