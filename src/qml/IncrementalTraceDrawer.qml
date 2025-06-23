import QtQuick

// Component for incremental trace drawing
Item {
    id: incrementalTraceDrawer
    
    // Properties for trace drawing
    property var pendulumObj: null
    property bool isDarkTheme: false
    property real massScaleFactorForRadius: 4.0
    property real traceLineWidth: 1.5
    
    // Canvas properties
    property int canvasWidth: 0
    property int canvasHeight: 0
    
    // Tracking properties with safe initial values
    property point lastScreenPointTrace1: Qt.point(-1, -1)
    property point lastScreenPointTrace2: Qt.point(-1, -1)

    // Maximum distance allowed between points to prevent "tails"
    property real maxDistanceForConnection: 50
    
    // Offscreen canvases for caching traces
    Canvas { 
        id: trace1OffscreenCanvas
        width: canvasWidth
        height: canvasHeight
        visible: false
        onPaint: {
            // Called when we manually request a paint
        }
    }
    
    Canvas { 
        id: trace2OffscreenCanvas
        width: canvasWidth
        height: canvasHeight
        visible: false
        onPaint: {
            // Called when we manually request a paint
        }
    }
    
    // Function to get the trace1 canvas
    function getTrace1Canvas() {
        return trace1OffscreenCanvas;
    }
    
    // Function to get the trace2 canvas
    function getTrace2Canvas() {
        return trace2OffscreenCanvas;
    }
    
    // Function to calculate visual state
    function calculateVisualState(pendulumObject, canvasWidth, canvasHeight, massScaleFactor) {
        if (!pendulumObject) return null;
        
        var centerX = canvasWidth / 2;
        var centerY = canvasHeight / 2;
        var phys_l1 = Math.max(0.01, pendulumObject.l1);
        var phys_l2 = Math.max(0.01, pendulumObject.l2);
        var maxPhysicalReach = phys_l1 + phys_l2;
        var targetScreenReach = Math.min(canvasWidth, canvasHeight) * 0.42;
        var globalScaleFactor = targetScreenReach / Math.max(0.1, maxPhysicalReach);
        
        return { 
            centerX: centerX, 
            centerY: centerY, 
            globalScaleFactor: globalScaleFactor
        };
    }
    
    // Function to clear all traces
    function clearAllTraces() {
        if (trace1OffscreenCanvas.available) {
            var ctx1 = trace1OffscreenCanvas.getContext("2d");
            ctx1.clearRect(0, 0, canvasWidth, canvasHeight);
        }
        
        if (trace2OffscreenCanvas.available) {
            var ctx2 = trace2OffscreenCanvas.getContext("2d");
            ctx2.clearRect(0, 0, canvasWidth, canvasHeight);
        }
        
        // Reset last points
        lastScreenPointTrace1 = Qt.point(-1, -1);
        lastScreenPointTrace2 = Qt.point(-1, -1);
    }
    
    // Function to update canvas dimensions
    function updateCanvasDimensions(width, height) {
        canvasWidth = width;
        canvasHeight = height;
        trace1OffscreenCanvas.width = width;
        trace1OffscreenCanvas.height = height;
        trace2OffscreenCanvas.width = width;
        trace2OffscreenCanvas.height = height;
    }
    
    // Function for incremental drawing of new trace segments
    function updateAndDrawNewTraceSegments(fullRedraw) {
        if (!pendulumObj || 
            !trace1OffscreenCanvas.available || 
            !trace2OffscreenCanvas.available ||
            canvasWidth <= 0 ||
            canvasHeight <= 0) {
            console.error("Cannot update traces: invalid state");
            return;
        }

        var visualState = calculateVisualState(pendulumObj, canvasWidth, canvasHeight, massScaleFactorForRadius);
        if (!visualState) {
            console.error("Cannot update traces: failed to calculate visual state");
            return;
        }

        var centerX = visualState.centerX;
        var centerY = visualState.centerY;
        var globalScaleFactor = visualState.globalScaleFactor;
        
        // --- Trace 1 ---
        if (pendulumObj.showTrace1) {
            if (fullRedraw) {
                // For full redraw, get all points and draw them at once
                var allTrace1Data = pendulumObj.getTrace1Points();
                
                if (allTrace1Data && allTrace1Data.length > 0) {
                    var ctx1 = trace1OffscreenCanvas.getContext("2d");
                    
                    // Clear canvas first
                    ctx1.clearRect(0, 0, canvasWidth, canvasHeight);
                    
                    // Draw complete path
                    ctx1.beginPath();
                    
                    // Move to the first point
                    var firstScreenPoint = Qt.point(
                        centerX + allTrace1Data[0].x * globalScaleFactor,
                        centerY + allTrace1Data[0].y * globalScaleFactor
                    );
                    
                    ctx1.moveTo(firstScreenPoint.x, firstScreenPoint.y);
                    
                    // Draw lines to all subsequent points
                    for (let i = 1; i < allTrace1Data.length; i++) {
                        var currentPoint = Qt.point(
                            centerX + allTrace1Data[i].x * globalScaleFactor,
                            centerY + allTrace1Data[i].y * globalScaleFactor
                        );
                        
                        // Check for big jumps that would create "tails"
                        var previousPoint = Qt.point(
                            centerX + allTrace1Data[i-1].x * globalScaleFactor,
                            centerY + allTrace1Data[i-1].y * globalScaleFactor
                        );
                        
                        var dist = Math.sqrt(
                            Math.pow(currentPoint.x - previousPoint.x, 2) + 
                            Math.pow(currentPoint.y - previousPoint.y, 2)
                        );
                        
                        // If distance is too large, move to the new point instead of drawing a line
                        if (dist > maxDistanceForConnection) {
                            ctx1.stroke(); // Complete the current path
                            ctx1.beginPath(); // Start a new path
                            ctx1.moveTo(currentPoint.x, currentPoint.y);
                        } else {
                            ctx1.lineTo(currentPoint.x, currentPoint.y);
                        }
                    }
                    
                    // Apply style and stroke
                    ctx1.strokeStyle = isDarkTheme ? 
                        "rgba(255, 100, 100, 0.7)" : "rgba(255, 0, 0, 0.5)";
                    ctx1.lineWidth = traceLineWidth;
                    ctx1.stroke();
                    
                    // Update last point for future incremental updates
                    if (allTrace1Data.length > 0) {
                        lastScreenPointTrace1 = Qt.point(
                            centerX + allTrace1Data[allTrace1Data.length - 1].x * globalScaleFactor,
                            centerY + allTrace1Data[allTrace1Data.length - 1].y * globalScaleFactor
                        );
                    }
                }
            } else {
                // For incremental update, consume only the new points
                var newPoints1 = pendulumObj.consumeNewTrace1Points();
                
                if (newPoints1 && newPoints1.length > 0) {
                    var ctx1 = trace1OffscreenCanvas.getContext("2d");
                    ctx1.beginPath();
                    
                    // Start drawing from last known point if it exists
                    var firstNewScreenPoint = Qt.point(
                        centerX + newPoints1[0].x * globalScaleFactor,
                        centerY + newPoints1[0].y * globalScaleFactor
                    );
                    
                    if (lastScreenPointTrace1.x !== -1) {
                        // Check distance to detect jumps
                        var dist = Math.sqrt(
                            Math.pow(firstNewScreenPoint.x - lastScreenPointTrace1.x, 2) + 
                            Math.pow(firstNewScreenPoint.y - lastScreenPointTrace1.y, 2)
                        );
                        
                        if (dist <= maxDistanceForConnection) {
                            ctx1.moveTo(lastScreenPointTrace1.x, lastScreenPointTrace1.y);
                            ctx1.lineTo(firstNewScreenPoint.x, firstNewScreenPoint.y);
                        } else {
                            // Distance too large, just start a new segment
                            ctx1.moveTo(firstNewScreenPoint.x, firstNewScreenPoint.y);
                        }
                    } else {
                        // No previous point, just start from the first new point
                        ctx1.moveTo(firstNewScreenPoint.x, firstNewScreenPoint.y);
                    }
                    
                    // Draw lines between all new points
                    var lastDrawnPoint = firstNewScreenPoint;
                    
                    for (let i = 1; i < newPoints1.length; i++) {
                        var currentScreenPoint = Qt.point(
                            centerX + newPoints1[i].x * globalScaleFactor,
                            centerY + newPoints1[i].y * globalScaleFactor
                        );
                        
                        // Check distance to previous point
                        var segmentDist = Math.sqrt(
                            Math.pow(currentScreenPoint.x - lastDrawnPoint.x, 2) + 
                            Math.pow(currentScreenPoint.y - lastDrawnPoint.y, 2)
                        );
                        
                        if (segmentDist <= maxDistanceForConnection) {
                            ctx1.lineTo(currentScreenPoint.x, currentScreenPoint.y);
                            lastDrawnPoint = currentScreenPoint;
                        } else {
                            // Complete this segment
                            ctx1.stroke();
                            
                            // Start a new segment
                            ctx1.beginPath();
                            ctx1.moveTo(currentScreenPoint.x, currentScreenPoint.y);
                            lastDrawnPoint = currentScreenPoint;
                        }
                    }
                    
                    // Apply style and stroke
                    ctx1.strokeStyle = isDarkTheme ? 
                        "rgba(255, 100, 100, 0.7)" : "rgba(255, 0, 0, 0.5)";
                    ctx1.lineWidth = traceLineWidth;
                    ctx1.stroke();
                    
                    // Update last point for next time
                    if (newPoints1.length > 0) {
                        lastScreenPointTrace1 = Qt.point(
                            centerX + newPoints1[newPoints1.length - 1].x * globalScaleFactor,
                            centerY + newPoints1[newPoints1.length - 1].y * globalScaleFactor
                        );
                    }
                }
            }
        }
        
        // --- Trace 2 ---
        if (pendulumObj.showTrace2) {
            if (fullRedraw) {
                // For full redraw, get all points and draw them at once
                var allTrace2Data = pendulumObj.getTrace2Points();
                
                if (allTrace2Data && allTrace2Data.length > 0) {
                    var ctx2 = trace2OffscreenCanvas.getContext("2d");
                    
                    // Clear canvas first
                    ctx2.clearRect(0, 0, canvasWidth, canvasHeight);
                    
                    // Draw complete path
                    ctx2.beginPath();
                    
                    // Move to the first point
                    var firstScreenPoint = Qt.point(
                        centerX + allTrace2Data[0].x * globalScaleFactor,
                        centerY + allTrace2Data[0].y * globalScaleFactor
                    );
                    
                    ctx2.moveTo(firstScreenPoint.x, firstScreenPoint.y);
                    
                    // Draw lines to all subsequent points
                    for (let i = 1; i < allTrace2Data.length; i++) {
                        var currentPoint = Qt.point(
                            centerX + allTrace2Data[i].x * globalScaleFactor,
                            centerY + allTrace2Data[i].y * globalScaleFactor
                        );
                        
                        // Check for big jumps that would create "tails"
                        var previousPoint = Qt.point(
                            centerX + allTrace2Data[i-1].x * globalScaleFactor,
                            centerY + allTrace2Data[i-1].y * globalScaleFactor
                        );
                        
                        var dist = Math.sqrt(
                            Math.pow(currentPoint.x - previousPoint.x, 2) + 
                            Math.pow(currentPoint.y - previousPoint.y, 2)
                        );
                        
                        // If distance is too large, move to the new point instead of drawing a line
                        if (dist > maxDistanceForConnection) {
                            ctx2.stroke(); // Complete the current path
                            ctx2.beginPath(); // Start a new path
                            ctx2.moveTo(currentPoint.x, currentPoint.y);
                        } else {
                            ctx2.lineTo(currentPoint.x, currentPoint.y);
                        }
                    }
                    
                    // Apply style and stroke
                    ctx2.strokeStyle = isDarkTheme ? 
                        "rgba(100, 100, 255, 0.7)" : "rgba(0, 0, 255, 0.5)";
                    ctx2.lineWidth = traceLineWidth;
                    ctx2.stroke();
                    
                    // Update last point for future incremental updates
                    if (allTrace2Data.length > 0) {
                        lastScreenPointTrace2 = Qt.point(
                            centerX + allTrace2Data[allTrace2Data.length - 1].x * globalScaleFactor,
                            centerY + allTrace2Data[allTrace2Data.length - 1].y * globalScaleFactor
                        );
                    }
                }
            } else {
                // For incremental update, consume only the new points
                var newPoints2 = pendulumObj.consumeNewTrace2Points();
                
                if (newPoints2 && newPoints2.length > 0) {
                    var ctx2 = trace2OffscreenCanvas.getContext("2d");
                    ctx2.beginPath();
                    
                    // Start drawing from last known point if it exists
                    var firstNewScreenPoint = Qt.point(
                        centerX + newPoints2[0].x * globalScaleFactor,
                        centerY + newPoints2[0].y * globalScaleFactor
                    );
                    
                    if (lastScreenPointTrace2.x !== -1) {
                        // Check distance to detect jumps
                        var dist = Math.sqrt(
                            Math.pow(firstNewScreenPoint.x - lastScreenPointTrace2.x, 2) + 
                            Math.pow(firstNewScreenPoint.y - lastScreenPointTrace2.y, 2)
                        );
                        
                        if (dist <= maxDistanceForConnection) {
                            ctx2.moveTo(lastScreenPointTrace2.x, lastScreenPointTrace2.y);
                            ctx2.lineTo(firstNewScreenPoint.x, firstNewScreenPoint.y);
                        } else {
                            // Distance too large, just start a new segment
                            ctx2.moveTo(firstNewScreenPoint.x, firstNewScreenPoint.y);
                        }
                    } else {
                        // No previous point, just start from the first new point
                        ctx2.moveTo(firstNewScreenPoint.x, firstNewScreenPoint.y);
                    }
                    
                    // Draw lines between all new points
                    var lastDrawnPoint = firstNewScreenPoint;
                    
                    for (let i = 1; i < newPoints2.length; i++) {
                        var currentScreenPoint = Qt.point(
                            centerX + newPoints2[i].x * globalScaleFactor,
                            centerY + newPoints2[i].y * globalScaleFactor
                        );
                        
                        // Check distance to previous point
                        var segmentDist = Math.sqrt(
                            Math.pow(currentScreenPoint.x - lastDrawnPoint.x, 2) + 
                            Math.pow(currentScreenPoint.y - lastDrawnPoint.y, 2)
                        );
                        
                        if (segmentDist <= maxDistanceForConnection) {
                            ctx2.lineTo(currentScreenPoint.x, currentScreenPoint.y);
                            lastDrawnPoint = currentScreenPoint;
                        } else {
                            // Complete this segment
                            ctx2.stroke();
                            
                            // Start a new segment
                            ctx2.beginPath();
                            ctx2.moveTo(currentScreenPoint.x, currentScreenPoint.y);
                            lastDrawnPoint = currentScreenPoint;
                        }
                    }
                    
                    // Apply style and stroke
                    ctx2.strokeStyle = isDarkTheme ? 
                        "rgba(100, 100, 255, 0.7)" : "rgba(0, 0, 255, 0.5)";
                    ctx2.lineWidth = traceLineWidth;
                    ctx2.stroke();
                    
                    // Update last point for next time
                    if (newPoints2.length > 0) {
                        lastScreenPointTrace2 = Qt.point(
                            centerX + newPoints2[newPoints2.length - 1].x * globalScaleFactor,
                            centerY + newPoints2[newPoints2.length - 1].y * globalScaleFactor
                        );
                    }
                }
            }
        }
    }
} 