#ifndef SPLASHSCREENHANDLER_H
#define SPLASHSCREENHANDLER_H

#include <QObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QDebug>
#include <QCoreApplication>
#include "core/DoublePendulum.h"

class SplashScreenHandler : public QObject
{
    Q_OBJECT

public:
    explicit SplashScreenHandler(QQmlApplicationEngine* engine,
                                DoublePendulum* pendulum,
                                QQuickWindow* splashWindow,
                                QObject* parent = nullptr);

public slots:
    void onRequestContinueToMainApplication();

private:
    QQmlApplicationEngine* m_engine;
    DoublePendulum* m_pendulum;
    QQuickWindow* m_splashWindow;
};

#endif // SPLASHSCREENHANDLER_H 