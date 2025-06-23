#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <cmath>
#include "core/DoublePendulum.h"
#include <QMetaType>
#include <QList>
#include <QPointF>
#include <QQuickStyle>
#include <QDir>
#include <QDebug>
#include <QUrl>
#include <QQuickWindow>
#include "ui/SplashScreenHandler.h"

int main(int argc, char *argv[])
{
    qRegisterMetaType<QList<QPointF>>("QList<QPointF>");
    
    // Register the DoublePendulum class as a QML type so its enums are accessible
    // Using "PendulumApi" as the QML type name to avoid collision with the 3D model component
    qmlRegisterType<DoublePendulum>("DoublePendulum", 1, 0, "PendulumApi");

    QApplication app(argc, argv);
    
    QQuickStyle::setStyle("Fusion");

    // Create the pendulum instance with initial parameters
    // Parameters: m1, m2, rodMass1, rodMass2, l1, l2, b1, b2, c1, c2, g, theta1, omega1, theta2, omega2
    DoublePendulum *pendulum = new DoublePendulum(
        1.0, 1.0,            // m1, m2 (point masses, 1kg each)
        0.5, 0.5,            // rodMass1, rodMass2 (rod masses, 0.5kg each)
        1.0, 1.0,            // l1, l2 (rod lengths, 1m each)
        0.0, 0.0,            // b1, b2 (linear friction coefficients)
        0.0, 0.0,            // c1, c2 (air resistance coefficients)
        9.81,                // g (gravity acceleration, m/s^2)
        M_PI / 4, 0.0,       // theta1, omega1 (initial angle 45 degrees, no initial velocity)
        M_PI / 4, 0.0,       // theta2, omega2 (relative angle is 45 deg)
        nullptr              // parent
    );

    QQmlApplicationEngine engine;
    
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    // First, load the splash screen
    engine.load(QUrl(QStringLiteral("qrc:/SplashScreen.qml")));
    if (engine.rootObjects().isEmpty()) {
        qDebug() << "Failed to load splash screen!";
        return -1;
    }
    
    // Get the splash screen window
    QObject *splashRootObject = engine.rootObjects().first();
    QQuickWindow *splashScreenWindow = qobject_cast<QQuickWindow *>(splashRootObject);
    
    if (!splashScreenWindow) {
        qDebug() << "Failed to get splash screen window!";
        return -1;
    }
    
    // Create the handler object
    SplashScreenHandler *handler = new SplashScreenHandler(&engine, pendulum, splashScreenWindow, &app);
    
    // Connect the QML signal to the handler's slot
    bool connected = QObject::connect(
        splashRootObject, 
        SIGNAL(requestContinueToMainApplication()),
        handler, 
        SLOT(onRequestContinueToMainApplication())
    );
    
    if (!connected) {
        qWarning() << "CRITICAL: Failed to connect QML signal to C++ slot!";
        qWarning() << "Application will continue but the splash screen transition may not work.";
    } else {
        qDebug() << "Successfully connected QML signal to C++ handler.";
    }
    
    return app.exec();
}
