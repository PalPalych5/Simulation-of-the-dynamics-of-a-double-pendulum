#include "../../include/ui/SplashScreenHandler.h"
#include <QCoreApplication>

SplashScreenHandler::SplashScreenHandler(QQmlApplicationEngine* engine,
                                       DoublePendulum* pendulum,
                                       QQuickWindow* splashWindow,
                                       QObject* parent)
    : QObject(parent)
    , m_engine(engine)
    , m_pendulum(pendulum)
    , m_splashWindow(splashWindow)
{
}

void SplashScreenHandler::onRequestContinueToMainApplication()
{
    qDebug() << "Signal requestContinueToMainApplication received.";
    
    // 1. Очищаем кеш компонентов, если это действительно нужно перед загрузкой нового модуля
    m_engine->clearComponentCache(); 
    
    // 2. Устанавливаем контекстное свойство
    m_engine->rootContext()->setContextProperty("pendulum", m_pendulum);
    
    // 3. Загружаем главный QML
    qDebug() << "Loading Main.qml...";
    m_engine->loadFromModule("DoublePendulum", "Main");
    
    if (m_engine->rootObjects().isEmpty()) {
        qWarning() << "CRITICAL: Failed to load Main.qml! Application will exit.";
        if (m_splashWindow) {
            m_splashWindow->close(); // Закрыть сплэш, если главное окно не загрузилось
        }
        QCoreApplication::exit(-1); // Выход из приложения
        return;
    } else {
        qDebug() << "Main.qml loaded successfully.";
        // Главное окно должно само установит себе visible: true.
    }

    // 4. Теперь, когда главное окно загружено, можно скрыть сплэш-окно
    if (m_splashWindow) {
        qDebug() << "Hiding splash screen.";
        m_splashWindow->hide(); 
        // Можно запланировать удаление сплэш-окна, если оно больше не нужно
        // m_splashWindow->deleteLater(); 
    }
} 