cmake_minimum_required(VERSION 3.16)

project(DoublePendulum VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Widgets Quick3D)

qt_standard_project_setup(REQUIRES 6.8)

# Explicitly list headers with Q_OBJECT for MOC
set(PROJECT_HEADERS
    include/core/DoublePendulum.h
    include/ui/SplashScreenHandler.h
)

# Add include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/include/core
    ${CMAKE_CURRENT_SOURCE_DIR}/include/ui
)

qt_add_executable(appDoublePendulum
    main.cpp
    src/core/DoublePendulum.cpp
    src/ui/SplashScreenHandler.cpp
    ${PROJECT_HEADERS}
    resources/resources.qrc
)

# Добавляем файл ресурсов с иконкой ТОЛЬКО для Windows
if(WIN32)
    target_sources(appDoublePendulum PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/resources/app.rc
    )
endif()

qt_add_qml_module(appDoublePendulum
    URI DoublePendulum
    VERSION 1.0
    QML_FILES
        src/qml/Main.qml
        src/qml/ChartPlaceholder.qml
        src/qml/ParameterStepper.qml
        src/qml/SplashScreen.qml
        src/qml/IncrementalTraceDrawer.qml
        src/qml/PendulumCanvas2D.qml
        src/qml/HelpPopup.qml
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(appDoublePendulum PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.appDoublePendulum
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appDoublePendulum
    PRIVATE Qt6::Quick
            Qt6::QuickControls2
            Qt6::Widgets
            Qt6::Quick3D
)

include(GNUInstallDirs)
install(TARGETS appDoublePendulum
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
