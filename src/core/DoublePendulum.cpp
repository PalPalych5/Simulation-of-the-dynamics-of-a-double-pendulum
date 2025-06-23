#include "core/DoublePendulum.h"
#include <cmath>
#include <algorithm>
#include <QDebug>
#include <QFile>
#include <QTextStream>
#include <QElapsedTimer>
#include <QTimer>
#include <functional>

// Since C++17, static constexpr members are implicitly inline, so they don't need a separate definition.
// If using an older standard, these definitions would be necessary:
// constexpr double DoublePendulum::DOPRI_ATOL;
// ...etc.

DoublePendulum::DoublePendulum(
    double m1, double m2,
    double rodMass1, double rodMass2,
    double l1, double l2,
    double b1, double b2,
    double c1, double c2,
    double g,
    double theta1_abs, double omega1,
    double theta2_rel, double omega2,
    QObject *parent)
    : QObject(parent)
    , m1(m1), m2(m2)
    , m_rodMass1(rodMass1), m_rodMass2(rodMass2)
    , l1(l1), l2(l2)
    , b1(b1), b2(b2)
    , c1(c1), c2(c2)
    , g(g)
    , theta1(theta1_abs), omega1(omega1)
    , theta2(theta2_rel), omega2(omega2)
    , m_simulationSpeed(1.0)
    , m_simulationFailed(false)
    , m_showTrace1(false)
    , m_showTrace2(false)
    , prev_theta1_for_poincare(theta1_abs) // Инициализация переменной для карты Пуанкаре
    , m_currentKineticEnergy(0.0)
    , m_currentPotentialEnergy(0.0)
    , m_currentTotalEnergy(0.0)
    , m_last_used_h(0.001)  // Инициализация с разумным начальным шагом
    , m_time_accumulator(0.0) // Начальное значение аккумулятора времени
    , m_fsal_ready(false)
    , m_last_fsal_t(0.0)
    , m_last_fsal_k(4, 0.0) // Assuming a 4-dimensional system
{
    // Начальные настройки уже определены в .h файле

    // Инициализация и настройка таймера вспышки для второго боба
    m_bob2FlashTimer = new QTimer(this);
    m_bob2FlashTimer->setSingleShot(true);
    m_bob2FlashTimer->setInterval(POINCARE_FLASH_DURATION_MS); // Длительность вспышки в мс
    connect(m_bob2FlashTimer, &QTimer::timeout, this, &DoublePendulum::resetBob2Flash);
}

void DoublePendulum::step(double dt)
{
    QElapsedTimer timer;
    timer.start();
    const double MAX_CALCULATION_TIME_MS = dt * 1000 * 0.8; // Use 80% of the frame time for calculation

    double target_sim_time_to_advance = dt * m_simulationSpeed + m_time_accumulator;
    m_time_accumulator = 0.0;

    double time_advanced_this_call = 0.0;
    double current_h = m_last_used_h;
    std::vector<double> y_current_state = {theta1, omega1, theta2, omega2};
    std::vector<double> y_next_state(4);
    bool step_accepted_flag;

    while (time_advanced_this_call < target_sim_time_to_advance && !m_simulationFailed) {
        if (timer.elapsed() > MAX_CALCULATION_TIME_MS) {
            m_time_accumulator = target_sim_time_to_advance - time_advanced_this_call;
            break;
        }

        double time_remaining = target_sim_time_to_advance - time_advanced_this_call;
        if (current_h > time_remaining) {
            if (time_remaining < DOPRI_HMIN / 2.0) {
                m_time_accumulator = time_remaining;
                break;
            }
            current_h = time_remaining;
        }
        
        double current_h_before_call = current_h;
        performOneDormandPrinceStep(m_currentTimeForHistory, y_current_state, current_h, y_next_state, step_accepted_flag);

        if (step_accepted_flag) {
            if (m_isManualControlActive) { // If manual control was somehow activated mid-step, abort history writing
                return;
            }
            y_current_state = y_next_state;
            m_currentTimeForHistory += current_h_before_call;
            time_advanced_this_call += current_h_before_call;

            for (const double& val : y_current_state) {
                if (std::isnan(val) || std::isinf(val)) {
                    m_simulationFailed = true;
                    emit simulationFailedChanged();
                    return; // Exit immediately
                }
            }

            m_theta1History.append(QPointF(m_currentTimeForHistory, y_current_state[0]));
            m_omega1History.append(QPointF(m_currentTimeForHistory, y_current_state[1]));
            m_theta2History.append(QPointF(m_currentTimeForHistory, y_current_state[2]));
            m_omega2History.append(QPointF(m_currentTimeForHistory, y_current_state[3]));

            // Update energies and traces using helper functions
            updateEnergies(y_current_state);
            updateTraces(y_current_state);

            // Update energy history
            m_kineticEnergyHistory.append(QPointF(m_currentTimeForHistory, m_currentKineticEnergy));
            m_potentialEnergyHistory.append(QPointF(m_currentTimeForHistory, m_currentPotentialEnergy));
            m_totalEnergyHistory.append(QPointF(m_currentTimeForHistory, m_currentTotalEnergy));

            // Poincare map logic
            if (((prev_theta1_for_poincare < 0 && y_current_state[0] >= 0) || (prev_theta1_for_poincare > 0 && y_current_state[0] <= 0)) && 
                std::abs(y_current_state[0]) < POINCARE_THETA1_TOLERANCE_RAD && 
                y_current_state[1] > POINCARE_OMEGA1_MIN_VELOCITY_RAD_S) {
                m_poincareMapPoints.append(QPointF(y_current_state[2], y_current_state[3]));
                if (!m_bob2PoincareFlash) {
                    m_bob2PoincareFlash = true;
                    emit bob2PoincareFlashChanged();
                }
                m_bob2FlashTimer->start();
            }
            prev_theta1_for_poincare = y_current_state[0];
        }

        // Prune history buffers if they exceed the maximum size
        if (m_theta1History.size() > MAX_BUFFER_SIZE) {
            m_theta1History.removeFirst();
            m_omega1History.removeFirst();
            m_theta2History.removeFirst();
            m_omega2History.removeFirst();
            m_kineticEnergyHistory.removeFirst();
            m_potentialEnergyHistory.removeFirst();
            m_totalEnergyHistory.removeFirst();
        }

        if (current_h < DOPRI_HMIN && !step_accepted_flag) {
            m_simulationFailed = true;
            emit simulationFailedChanged();
            break;
        }
        m_last_used_h = current_h;
    }

    if (!m_simulationFailed) {
        theta1 = y_current_state[0];
        omega1 = y_current_state[1];
        theta2 = y_current_state[2];
        omega2 = y_current_state[3];
        if (time_advanced_this_call > 0) {
            emit historyUpdated();
            emit currentTimeChanged();
        }
    }

    emit theta1Changed();
    emit theta2Changed();
    emit omega1Changed();
    emit omega2Changed();
    emit stateChanged();
}

double DoublePendulum::getTheta1() const { return theta1; }
double DoublePendulum::getOmega1() const { return omega1; }
double DoublePendulum::getTheta2() const { return theta2; }
double DoublePendulum::getOmega2() const { return omega2; }

void DoublePendulum::setTheta1(double newTheta1) {
    if (theta1 != newTheta1) {
        theta1 = newTheta1;
        emit theta1Changed();
        emit stateChanged();
    }
}

void DoublePendulum::setTheta2(double newTheta2) {
    if (theta2 != newTheta2) {
        theta2 = newTheta2;
        emit theta2Changed();
        emit stateChanged();
    }
}

/*
 * @brief Calculates the derivatives of the state vector.
 *
 * This function implements the core physics of the double pendulum. It solves
 * the system of linear equations A * x_ddot = B to find the angular
 * accelerations, where:
 *
 * x = [theta1_abs]
 *     [theta2_abs]
 *
 * x_ddot = [theta1_abs_ddot] -> angular acceleration of the first pendulum
 *          [theta2_abs_ddot] -> angular acceleration of the second pendulum
 *
 * A = [[ A11, A12 ],  // The mass matrix, dependent on the current state.
 *      [ A21, A22 ]]
 *
 * B = [[ B1 ],        // Vector of forces (gravity, centrifugal, Coriolis, friction).
 *      [ B2 ]]
 *
 * The function returns the state derivative vector dy/dt:
 * {omega1_abs, theta1_abs_ddot, omega2_rel, theta2_rel_ddot}
 */
std::vector<double> DoublePendulum::getDerivatives(double t, const std::vector<double>& yState) const {
    (void)t; // Mark 't' as unused to avoid compiler warnings

    double current_theta1_abs = yState[0];
    double current_omega1_abs = yState[1];
    double current_theta2_rel = yState[2];
    double current_omega2_rel_dot = yState[3];
    double current_theta2_abs = current_theta1_abs + current_theta2_rel;
    double current_omega2_abs = current_omega1_abs + current_omega2_rel_dot;

    double A11 = (m1 + m_rodMass1/3.0 + m2 + m_rodMass2) * l1 * l1;
    double A12 = (m2 + m_rodMass2/2.0) * l1 * l2 * cos(current_theta1_abs - current_theta2_abs);
    double A21 = A12;
    double A22 = (m2 + m_rodMass2/3.0) * l2 * l2;

    double Q_nc1 = -b1 * current_omega1_abs - c1 * current_omega1_abs * std::abs(current_omega1_abs);
    double Q_nc2 = -b2 * current_omega2_rel_dot - c2 * current_omega2_rel_dot * std::abs(current_omega2_rel_dot);

    double B1 = -(m2 + m_rodMass2/2.0) * l1 * l2 * current_omega2_abs * current_omega2_abs * sin(current_theta1_abs - current_theta2_abs)
                - g * (m1 + m_rodMass1/2.0 + m2 + m_rodMass2) * l1 * sin(current_theta1_abs)
                + Q_nc1;
    double B2 = (m2 + m_rodMass2/2.0) * l1 * l2 * current_omega1_abs * current_omega1_abs * sin(current_theta1_abs - current_theta2_abs)
                - g * (m2 + m_rodMass2/2.0) * l2 * sin(current_theta2_abs)
                + Q_nc2;

    double det = A11 * A22 - A12 * A21;
    if (std::fabs(det) < 1e-12) { // Use a slightly larger epsilon for singularity check
        return {current_omega1_abs, 0.0, current_omega2_rel_dot, 0.0};
    }

    double theta1_abs_ddot = (B1 * A22 - A12 * B2) / det;
    double theta2_abs_ddot = (A11 * B2 - B1 * A21) / det;
    double theta2_rel_ddot = theta2_abs_ddot - theta1_abs_ddot;

    return {current_omega1_abs, theta1_abs_ddot, current_omega2_rel_dot, theta2_rel_ddot};
}

void DoublePendulum::reset(double newTheta1_abs, double newOmega1, double newTheta2_rel, double newOmega2) {
    qDebug() << "C++ DoublePendulum::reset called with params:" << 
                "\ntheta1_abs_rad=" << newTheta1_abs << " (" << newTheta1_abs * 180.0/M_PI << "°)" <<
                "\nomega1=" << newOmega1 <<
                "\ntheta2_rel_rad=" << newTheta2_rel << " (" << newTheta2_rel * 180.0/M_PI << "°)" <<
                "\nomega2=" << newOmega2;
                
    // Обновить состояние
    theta1 = newTheta1_abs;
    omega1 = newOmega1;
    theta2 = newTheta2_rel;
    omega2 = newOmega2;
    
    // Очищаем исторические данные
    m_theta1History.clear();
    m_theta2History.clear();
    m_omega1History.clear();
    m_omega2History.clear();
    m_kineticEnergyHistory.clear();
    m_potentialEnergyHistory.clear();
    m_totalEnergyHistory.clear();
    
    // Добавляем начальные значения
    m_theta1History.append(QPointF(0, theta1));
    m_theta2History.append(QPointF(0, theta2));
    m_omega1History.append(QPointF(0, omega1));
    m_omega2History.append(QPointF(0, omega2));
    
    // Очищаем трассы
    m_trace1_points.clear();
    m_trace2_points.clear();
    
    // Сбрасываем текущее время
    m_currentTimeForHistory = 0.0;
    emit currentTimeChanged(); // Emit signal when time is reset
    
    // Сбрасываем параметры интегрирования
    m_last_used_h = 0.001;     // Возвращаем начальный шаг
    m_time_accumulator = 0.0;  // Сбрасываем аккумулятор времени
    
    // Сбрасываем FSAL оптимизацию
    m_fsal_ready = false;
    
    // Сбрасываем карту Пуанкаре
    prev_theta1_for_poincare = theta1;
    m_poincareMapPoints.clear();
    
    // Сбрасываем флаг ошибки симуляции
    if (m_simulationFailed) {
        m_simulationFailed = false;
        emit simulationFailedChanged();
    }
    
    // Recalculate initial energy using the helper function
    updateEnergies({theta1, omega1, theta2, omega2});

    // Add initial state to history
    m_theta1History.append(QPointF(0, theta1));
    m_theta2History.append(QPointF(0, theta2));
    m_omega1History.append(QPointF(0, omega1));
    m_omega2History.append(QPointF(0, omega2));
    m_kineticEnergyHistory.append(QPointF(0, m_currentKineticEnergy));
    m_potentialEnergyHistory.append(QPointF(0, m_currentPotentialEnergy));
    m_totalEnergyHistory.append(QPointF(0, m_currentTotalEnergy));

    emit theta1Changed();
    emit theta2Changed();
    emit omega1Changed();
    emit omega2Changed();
    emit stateChanged();
    emit historyUpdated();
    emit currentKineticEnergyChanged();
    emit currentPotentialEnergyChanged();
    emit currentTotalEnergyChanged();
    emit currentTimeChanged();
}

void DoublePendulum::updateEnergies(const std::vector<double>& state) {
    double theta1_abs = state[0];
    double omega1_abs = state[1];
    double theta2_rel = state[2];
    double omega2_rel = state[3];

    double theta2_abs = theta1_abs + theta2_rel;
    double omega2_abs = omega1_abs + omega2_rel;

    // Kinetic Energy T = T1 + T2
    double T1 = 0.5 * (m1 + m_rodMass1 / 3.0) * l1 * l1 * omega1_abs * omega1_abs;
    double T2 = 0.5 * (m2 + m_rodMass2) * l1 * l1 * omega1_abs * omega1_abs +
                0.5 * (m2 + m_rodMass2 / 3.0) * l2 * l2 * omega2_abs * omega2_abs +
                (m2 + m_rodMass2 / 2.0) * l1 * l2 * omega1_abs * omega2_abs * cos(theta2_rel);
    m_currentKineticEnergy = T1 + T2;

    // Potential Energy V = V1 + V2 (relative to suspension point y=0)
    double V1 = (m1 + m_rodMass1 / 2.0 + m2 + m_rodMass2) * g * l1 * cos(theta1_abs);
    double V2 = (m2 + m_rodMass2 / 2.0) * g * l2 * cos(theta2_abs);
    m_currentPotentialEnergy = -(V1 + V2); // Negative because y is downwards from origin

    m_currentTotalEnergy = m_currentKineticEnergy + m_currentPotentialEnergy;
}

void DoublePendulum::updateTraces(const std::vector<double>& state) {
    if (m_isManualControlActive) { // Don't update traces when in manual control mode
        return;
    }
    
    if (!m_showTrace1 && !m_showTrace2) {
        return;
    }

    double x1_phys = l1 * std::sin(state[0]);
    double y1_phys = l1 * std::cos(state[0]);

    if (m_showTrace1) {
        QPointF newPoint(x1_phys, y1_phys);
        // Add point only if it's far enough from the previous one
        if (m_trace1_points.empty() || calculateDistance(m_trace1_points.back(), newPoint) > MIN_TRACE_DISTANCE) {
            m_trace1_points.push_back(newPoint);
            m_new_trace1_points.push_back(newPoint); // Add to the incremental buffer
            
            // Prune trace buffer if it exceeds the maximum size
            if (m_trace1_points.size() > MAX_BUFFER_SIZE) {
                m_trace1_points.removeFirst();
            }
        }
    }

    if (m_showTrace2) {
        double theta2_abs = state[0] + state[2];
        double x2_phys = x1_phys + l2 * std::sin(theta2_abs);
        double y2_phys = y1_phys + l2 * std::cos(theta2_abs);
        QPointF newPoint(x2_phys, y2_phys);
        // Add point only if it's far enough
        if (m_trace2_points.empty() || calculateDistance(m_trace2_points.back(), newPoint) > MIN_TRACE_DISTANCE) {
            m_trace2_points.push_back(newPoint);
            m_new_trace2_points.push_back(newPoint); // Add to the incremental buffer
            
            // Prune trace buffer if it exceeds the maximum size
            if (m_trace2_points.size() > MAX_BUFFER_SIZE) {
                m_trace2_points.removeFirst();
            }
        }
    }
}

double DoublePendulum::getM1() const { return m1; }
double DoublePendulum::getM2() const { return m2; }

void DoublePendulum::setM1(double newM1) {
    double clampedM1 = std::max(0.01, std::min(newM1, 30.0));
    if (m1 != clampedM1) {
        m1 = clampedM1;
        emit m1Changed();
    }
}

void DoublePendulum::setM2(double newM2) {
    double clampedM2 = std::max(0.01, std::min(newM2, 30.0));
    if (m2 != clampedM2) {
        m2 = clampedM2;
        emit m2Changed();
    }
}

double DoublePendulum::getRodMass1() const { return m_rodMass1; }
double DoublePendulum::getRodMass2() const { return m_rodMass2; }

void DoublePendulum::setRodMass1(double newRodMass1) {
    double clamped = std::max(0.0, std::min(newRodMass1, 10.0));
    if (m_rodMass1 != clamped) {
        m_rodMass1 = clamped;
        emit rodMass1Changed();
    }
}

void DoublePendulum::setRodMass2(double newRodMass2) {
    double clamped = std::max(0.0, std::min(newRodMass2, 10.0));
    if (m_rodMass2 != clamped) {
        m_rodMass2 = clamped;
        emit rodMass2Changed();
    }
}

// Getters and setters for rod lengths
double DoublePendulum::getL1() const { return l1; }
double DoublePendulum::getL2() const { return l2; }

void DoublePendulum::setL1(double newL1) {
    double clamped = std::max(0.1, std::min(newL1, 5.0));
    if (l1 != clamped) {
        l1 = clamped;
        emit l1Changed();
    }
}

void DoublePendulum::setL2(double newL2) {
    double clamped = std::max(0.1, std::min(newL2, 5.0));
    if (l2 != clamped) {
        l2 = clamped;
        emit l2Changed();
    }
}

// Getters and setters for friction coefficients
double DoublePendulum::getB1() const { return b1; }
double DoublePendulum::getB2() const { return b2; }

void DoublePendulum::setB1(double newB1) {
    double clamped = std::max(0.0, std::min(newB1, 10.0));
    if (b1 != clamped) {
        b1 = clamped;
        emit b1Changed();
    }
}

void DoublePendulum::setB2(double newB2) {
    double clamped = std::max(0.0, std::min(newB2, 10.0));
    if (b2 != clamped) {
        b2 = clamped;
        emit b2Changed();
    }
}

// Getters and setters for air resistance coefficients
double DoublePendulum::getC1() const { return c1; }
double DoublePendulum::getC2() const { return c2; }

void DoublePendulum::setC1(double newC1) {
    double clamped = std::max(0.0, std::min(newC1, 5.0));
    if (c1 != clamped) {
        c1 = clamped;
        emit c1Changed();
    }
}

void DoublePendulum::setC2(double newC2) {
    double clamped = std::max(0.0, std::min(newC2, 5.0));
    if (c2 != clamped) {
        c2 = clamped;
        emit c2Changed();
    }
}

// Getter and setter for gravity
double DoublePendulum::getG() const { return g; }

void DoublePendulum::setG(double newGValue) {
    double clamped = std::max(0.0, std::min(newGValue, 100.0));
    if (g != clamped) {
        g = clamped;
        emit gChanged();
    }
}

void DoublePendulum::setManualControl(bool isActive) {
    m_isManualControlActive = isActive;
}

double DoublePendulum::getSimulationSpeed() const { return m_simulationSpeed; }
void DoublePendulum::setSimulationSpeed(double newSpeed) {
    if (m_simulationSpeed != newSpeed && newSpeed > 0) {
        m_simulationSpeed = newSpeed;
        emit simulationSpeedChanged();
    }
}

bool DoublePendulum::getSimulationFailed() const { return m_simulationFailed; }

// New trace-related methods
bool DoublePendulum::getShowTrace1() const { return m_showTrace1; }
void DoublePendulum::setShowTrace1(bool show) {
    if (m_showTrace1 != show) {
        m_showTrace1 = show;
        emit showTrace1Changed();
    }
}

bool DoublePendulum::getShowTrace2() const { return m_showTrace2; }
void DoublePendulum::setShowTrace2(bool show) {
    if (m_showTrace2 != show) {
        m_showTrace2 = show;
        emit showTrace2Changed();
    }
}

QVector<QPointF> DoublePendulum::getTrace1Points() const { return m_trace1_points; }
QVector<QPointF> DoublePendulum::getTrace2Points() const { return m_trace2_points; }

void DoublePendulum::clearTraces() {
    m_trace1_points.clear();
    m_trace2_points.clear();
    m_new_trace1_points.clear();
    m_new_trace2_points.clear();
    emit historyUpdated();
}

QVector<QPointF> DoublePendulum::getTheta1History() const { return m_theta1History; }
QVector<QPointF> DoublePendulum::getTheta2History() const { return m_theta2History; }
QVector<QPointF> DoublePendulum::getOmega1History() const { return m_omega1History; }
QVector<QPointF> DoublePendulum::getOmega2History() const { return m_omega2History; }
QVector<QPointF> DoublePendulum::getKineticEnergyHistory() const { return m_kineticEnergyHistory; }
QVector<QPointF> DoublePendulum::getPotentialEnergyHistory() const { return m_potentialEnergyHistory; }
QVector<QPointF> DoublePendulum::getTotalEnergyHistory() const { return m_totalEnergyHistory; }
QVector<QPointF> DoublePendulum::getPoincareMapPoints() const { return m_poincareMapPoints; }

void DoublePendulum::clearHistory() {
    m_theta1History.clear();
    m_theta2History.clear();
    m_omega1History.clear();
    m_omega2History.clear();
    m_kineticEnergyHistory.clear();
    m_potentialEnergyHistory.clear();
    m_totalEnergyHistory.clear();
    m_poincareMapPoints.clear();
    m_currentTimeForHistory = 0.0;
    emit currentTimeChanged();
    emit historyUpdated();
}

void DoublePendulum::clearPoincareMapPoints() {
    m_poincareMapPoints.clear();
    emit historyUpdated();
}

double DoublePendulum::getCurrentKineticEnergy() const { return m_currentKineticEnergy; }
double DoublePendulum::getCurrentPotentialEnergy() const { return m_currentPotentialEnergy; }
double DoublePendulum::getCurrentTotalEnergy() const { return m_currentTotalEnergy; }
double DoublePendulum::getCurrentTime() const { return m_currentTimeForHistory; }

// Implementation of the saveTextToFile method
bool DoublePendulum::saveTextToFile(const QString &filePath, const QString &content) {
    if (filePath.isEmpty()) {
        qWarning() << "saveTextToFile: Empty file path provided";
        return false;
    }
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "saveTextToFile: Failed to open file for writing:" << filePath << "Error:" << file.errorString();
        return false;
    }
    QTextStream out(&file);
    out << content;
    file.close();
    return true;
}

void DoublePendulum::performOneDormandPrinceStep(
    double tCurrent,
    const std::vector<double>& yCurrent,
    double& hInOut,
    std::vector<double>& yNext,
    bool& stepAccepted
) {
    const int N = 4;
    const std::vector<double> c = {0.0, DP5_C2, DP5_C3, DP5_C4, DP5_C5, DP5_C6, DP5_C7};

    std::vector<std::vector<double>> k(7, std::vector<double>(N));
    std::vector<double> y_stage(N);

    if (m_fsal_ready && std::abs(tCurrent - m_last_fsal_t) < 1e-12) {
        k[0] = m_last_fsal_k;
    } else {
        k[0] = getDerivatives(tCurrent, yCurrent);
    }
    
    for(int j=0; j<N; ++j) y_stage[j] = yCurrent[j] + hInOut * (DP5_A21*k[0][j]);
    k[1] = getDerivatives(tCurrent + c[1]*hInOut, y_stage);
    
    for(int j=0; j<N; ++j) y_stage[j] = yCurrent[j] + hInOut * (DP5_A31*k[0][j] + DP5_A32*k[1][j]);
    k[2] = getDerivatives(tCurrent + c[2]*hInOut, y_stage);
    
    for(int j=0; j<N; ++j) y_stage[j] = yCurrent[j] + hInOut * (DP5_A41*k[0][j] + DP5_A42*k[1][j] + DP5_A43*k[2][j]);
    k[3] = getDerivatives(tCurrent + c[3]*hInOut, y_stage);
    
    for(int j=0; j<N; ++j) y_stage[j] = yCurrent[j] + hInOut * (DP5_A51*k[0][j] + DP5_A52*k[1][j] + DP5_A53*k[2][j] + DP5_A54*k[3][j]);
    k[4] = getDerivatives(tCurrent + c[4]*hInOut, y_stage);
    
    for(int j=0; j<N; ++j) y_stage[j] = yCurrent[j] + hInOut * (DP5_A61*k[0][j] + DP5_A62*k[1][j] + DP5_A63*k[2][j] + DP5_A64*k[3][j] + DP5_A65*k[4][j]);
    k[5] = getDerivatives(tCurrent + c[5]*hInOut, y_stage);
    
    for(int j=0; j<N; ++j) y_stage[j] = yCurrent[j] + hInOut * (DP5_A71*k[0][j] + DP5_A73*k[2][j] + DP5_A74*k[3][j] + DP5_A75*k[4][j] + DP5_A76*k[5][j]);
    k[6] = getDerivatives(tCurrent + c[6]*hInOut, y_stage);

    std::vector<double> ySol5(N);
    for (int j = 0; j < N; ++j) {
        ySol5[j] = yCurrent[j] + hInOut * (DP5_B1*k[0][j] + DP5_B2*k[1][j] + DP5_B3*k[2][j] + DP5_B4*k[3][j] + DP5_B5*k[4][j] + DP5_B6*k[5][j] + DP5_B7*k[6][j]);
    }
    
    double errNormSquare = 0.0;
    for (int j=0; j<N; ++j) {
        double error = hInOut * (DP5_E1*k[0][j] + DP5_E2*k[1][j] + DP5_E3*k[2][j] + DP5_E4*k[3][j] + DP5_E5*k[4][j] + DP5_E6*k[5][j] + DP5_E7*k[6][j]);
        double scale = DOPRI_ATOL + DOPRI_RTOL * std::max(std::abs(yCurrent[j]), std::abs(ySol5[j]));
        errNormSquare += (error*error) / (scale*scale);
    }
    double errNorm = std::sqrt(errNormSquare / N);

    stepAccepted = (errNorm <= 1.0);
    double hNew;
    if (errNorm < 1e-15) {
        hNew = hInOut * DOPRI_FAC_MAX;
    } else {
        hNew = DOPRI_SAFETY_FACTOR * hInOut * std::pow(errNorm, -0.2);
        hNew = std::min(hInOut * DOPRI_FAC_MAX, std::max(hInOut * DOPRI_FAC_MIN, hNew));
    }
    hInOut = std::min(DOPRI_HMAX, std::max(DOPRI_HMIN, hNew));

    if (stepAccepted) {
        yNext = ySol5;
        m_last_fsal_k = k[6];
        m_last_fsal_t = tCurrent + hInOut; // This should be current_h_before_call
        m_fsal_ready = true;
    } else {
        m_fsal_ready = false;
    }
}

// Новый метод для обработки временных рядов
QVariantList DoublePendulum::getProcessedTimeSeriesData(
    TimeSeriesType seriesType,
    double viewPortMinTime,
    double viewPortMaxTime,
    bool rdpEnabled,
    double rdpEpsilon,
    bool limitPointsEnabled,
    int maxPointsLimit
) {
    QVector<QPointF> sourceData;
    switch (seriesType) {
        case TimeSeriesType::Theta1_Degrees:
            sourceData = m_theta1History;
            for (int i = 0; i < sourceData.size(); ++i) sourceData[i].setY(sourceData[i].y() * 180.0 / M_PI);
            break;
        case TimeSeriesType::Theta2_Degrees:
            if (m_theta1History.size() > 0 && m_theta2History.size() > 0) {
                for (int i = 0; i < std::min(m_theta1History.size(), m_theta2History.size()); ++i) {
                    if (m_theta1History[i].x() == m_theta2History[i].x()) {
                        sourceData.append(QPointF(m_theta1History[i].x(), (m_theta1History[i].y() + m_theta2History[i].y()) * 180.0 / M_PI));
                    }
                }
            }
            break;
        case TimeSeriesType::Omega1_Rad_s: sourceData = m_omega1History; break;
        case TimeSeriesType::Omega2_Rad_s: sourceData = m_omega2History; break;
        case TimeSeriesType::KineticEnergy: sourceData = m_kineticEnergyHistory; break;
        case TimeSeriesType::PotentialEnergy: sourceData = m_potentialEnergyHistory; break;
        case TimeSeriesType::TotalEnergy: sourceData = m_totalEnergyHistory; break;
        default: return QVariantList();
    }

    QVector<QPointF> processedPoints;
    for (const QPointF& point : sourceData) {
        if (point.x() >= viewPortMinTime && point.x() <= viewPortMaxTime) {
            processedPoints.append(point);
        }
    }

    if (rdpEnabled && processedPoints.size() > 2 && rdpEpsilon > 0) {
        std::function<QVector<QPointF>(const QVector<QPointF>&, double)> simplifyRDP;
        auto perpendicularDistance = [](const QPointF& pt, const QPointF& p1, const QPointF& p2) {
            double dx = p2.x() - p1.x(), dy = p2.y() - p1.y();
            double mag = std::sqrt(dx*dx + dy*dy);
            if (mag>0.) {dx/=mag; dy/=mag;}
            double pvx = pt.x() - p1.x(), pvy = pt.y() - p1.y();
            return std::abs(pvx*dy - pvy*dx);
        };
        simplifyRDP = [&perpendicularDistance, &simplifyRDP](const QVector<QPointF>& points, double epsilon) -> QVector<QPointF> {
            if (points.size() <= 2) return points;
            double dmax = 0; int index = 0; int end = points.size() - 1;
            for (int i=1; i<end; ++i) {
                double d = perpendicularDistance(points[i], points[0], points[end]);
                if (d > dmax) { index = i; dmax = d; }
            }
            if (dmax > epsilon) {
                QVector<QPointF> res1 = simplifyRDP(points.mid(0, index + 1), epsilon);
                QVector<QPointF> res2 = simplifyRDP(points.mid(index), epsilon);
                return res1.mid(0, res1.size()-1) + res2;
            } else {
                return QVector<QPointF>{points.first(), points.last()};
            }
        };
        processedPoints = simplifyRDP(processedPoints, rdpEpsilon);
    }

    if (limitPointsEnabled && processedPoints.size() > maxPointsLimit) {
        if (maxPointsLimit > 0) {
            QVector<QPointF> subsampledPoints;
            double stride = static_cast<double>(processedPoints.size()) / maxPointsLimit;
            for (int i = 0; i < maxPointsLimit; ++i) {
                subsampledPoints.append(processedPoints.at(static_cast<int>(i * stride)));
            }
            processedPoints = subsampledPoints;
        } else {
            processedPoints.clear();
        }
    }

    QVariantList result;
    for (const QPointF& point : processedPoints) result.append(QVariant::fromValue(point));
    return result;
}

// Implementation of the bob2 flash getter
bool DoublePendulum::getBob2PoincareFlash() const {
    return m_bob2PoincareFlash;
}

// Implementation of the bob2 flash reset slot
void DoublePendulum::resetBob2Flash() {
    if (m_bob2PoincareFlash) {
        m_bob2PoincareFlash = false;
        emit bob2PoincareFlashChanged();
    }
}

// Helper function to calculate distance between points
double DoublePendulum::calculateDistance(const QPointF& p1, const QPointF& p2) const {
    return std::sqrt(std::pow(p2.x() - p1.x(), 2) + std::pow(p2.y() - p1.y(), 2));
}

// Methods for consuming new trace points
QVariantList DoublePendulum::consumeNewTrace1Points()
{
    QVariantList result;
    for (const QPointF& point : m_new_trace1_points) {
        result.append(QVariant::fromValue(point));
    }
    m_new_trace1_points.clear();
    return result;
}

QVariantList DoublePendulum::consumeNewTrace2Points()
{
    QVariantList result;
    for (const QPointF& point : m_new_trace2_points) {
        result.append(QVariant::fromValue(point));
    }
    m_new_trace2_points.clear();
    return result;
}

// Implementation of the new method for phase portrait data
QVariantList DoublePendulum::getPhasePortraitData(
    TimeSeriesType xSeries,
    TimeSeriesType ySeries
) {
    // Helper lambda to get the correct data vector based on enum
    auto getDataVector = [&](TimeSeriesType type) -> QVector<QPointF> {
        switch (type) {
            case TimeSeriesType::Theta1_Degrees:       return m_theta1History;
            case TimeSeriesType::Theta2_Degrees:       return m_theta2History; // Note: this is relative theta2
            case TimeSeriesType::Omega1_Rad_s:         return m_omega1History;
            case TimeSeriesType::Omega2_Rad_s:         return m_omega2History;
            case TimeSeriesType::KineticEnergy:        return m_kineticEnergyHistory;
            case TimeSeriesType::PotentialEnergy:      return m_potentialEnergyHistory;
            case TimeSeriesType::TotalEnergy:          return m_totalEnergyHistory;
            default:                                   return {};
        }
    };

    QVector<QPointF> xData = getDataVector(xSeries);
    QVector<QPointF> yData = getDataVector(ySeries);

    // Post-processing for degrees if needed
    if (xSeries == TimeSeriesType::Theta1_Degrees || xSeries == TimeSeriesType::Theta2_Degrees) {
        for(auto& point : xData) { point.setY(point.y() * 180.0 / M_PI); }
    }
    if (ySeries == TimeSeriesType::Theta1_Degrees || ySeries == TimeSeriesType::Theta2_Degrees) {
        for(auto& point : yData) { point.setY(point.y() * 180.0 / M_PI); }
    }

    // Special case: if theta2 is requested, it should be absolute angle
    if (xSeries == TimeSeriesType::Theta2_Degrees) {
        const auto& theta1Data = getDataVector(TimeSeriesType::Theta1_Degrees);
        for(int i = 0; i < xData.size() && i < theta1Data.size(); ++i) {
            xData[i].setY(xData[i].y() + (theta1Data[i].y() * 180.0 / M_PI));
        }
    }
    if (ySeries == TimeSeriesType::Theta2_Degrees) {
        const auto& theta1Data = getDataVector(TimeSeriesType::Theta1_Degrees);
         for(int i = 0; i < yData.size() && i < theta1Data.size(); ++i) {
            yData[i].setY(yData[i].y() + (theta1Data[i].y() * 180.0 / M_PI));
        }
    }

    QVariantList phaseData;
    int n = std::min(xData.size(), yData.size());
    phaseData.reserve(n);
    for (int i = 0; i < n; ++i) {
        // We assume timestamps are aligned, which they are by design
        phaseData.append(QPointF(xData[i].y(), yData[i].y()));
    }

    return phaseData;
}


