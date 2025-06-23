#ifndef DOUBLEPENDULUM_H
#define DOUBLEPENDULUM_H

#include <QObject>
#include <QTimer>
#include <QPointF>
#include <deque>
#include <algorithm>
#include <vector>
#include <QList>
#include <QMetaType>
#include <QString>
#include <QVariantList>
#include <QVector>

Q_DECLARE_METATYPE(QList<QPointF>)

class DoublePendulum : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double theta1 READ getTheta1 WRITE setTheta1 NOTIFY theta1Changed)
    Q_PROPERTY(double theta2 READ getTheta2 WRITE setTheta2 NOTIFY theta2Changed)
    Q_PROPERTY(double omega1 READ getOmega1 NOTIFY omega1Changed)
    Q_PROPERTY(double omega2 READ getOmega2 NOTIFY omega2Changed)
    Q_PROPERTY(double m1 READ getM1 WRITE setM1 NOTIFY m1Changed)
    Q_PROPERTY(double m2 READ getM2 WRITE setM2 NOTIFY m2Changed)
    Q_PROPERTY(double m1_rod READ getRodMass1 WRITE setRodMass1 NOTIFY rodMass1Changed)
    Q_PROPERTY(double m2_rod READ getRodMass2 WRITE setRodMass2 NOTIFY rodMass2Changed)
    Q_PROPERTY(double l1 READ getL1 WRITE setL1 NOTIFY l1Changed)
    Q_PROPERTY(double l2 READ getL2 WRITE setL2 NOTIFY l2Changed)
    Q_PROPERTY(double b1 READ getB1 WRITE setB1 NOTIFY b1Changed)
    Q_PROPERTY(double b2 READ getB2 WRITE setB2 NOTIFY b2Changed)
    Q_PROPERTY(double c1 READ getC1 WRITE setC1 NOTIFY c1Changed)
    Q_PROPERTY(double c2 READ getC2 WRITE setC2 NOTIFY c2Changed)
    Q_PROPERTY(double g READ getG WRITE setG NOTIFY gChanged)
    Q_PROPERTY(double simulationSpeed READ getSimulationSpeed WRITE setSimulationSpeed NOTIFY simulationSpeedChanged)
    Q_PROPERTY(bool simulationFailed READ getSimulationFailed NOTIFY simulationFailedChanged)
    Q_PROPERTY(bool showTrace1 READ getShowTrace1 WRITE setShowTrace1 NOTIFY showTrace1Changed)
    Q_PROPERTY(bool showTrace2 READ getShowTrace2 WRITE setShowTrace2 NOTIFY showTrace2Changed)
    Q_PROPERTY(double currentKineticEnergy READ getCurrentKineticEnergy NOTIFY currentKineticEnergyChanged)
    Q_PROPERTY(double currentPotentialEnergy READ getCurrentPotentialEnergy NOTIFY currentPotentialEnergyChanged)
    Q_PROPERTY(double currentTotalEnergy READ getCurrentTotalEnergy NOTIFY currentTotalEnergyChanged)
    Q_PROPERTY(double currentTime READ getCurrentTime NOTIFY currentTimeChanged)
    Q_PROPERTY(bool bob2PoincareFlash READ getBob2PoincareFlash NOTIFY bob2PoincareFlashChanged)

public:
    // Enum for time series types
    enum class TimeSeriesType {
        Theta1_Degrees,
        Theta2_Degrees,
        Omega1_Rad_s,
        Omega2_Rad_s,
        KineticEnergy,
        PotentialEnergy,
        TotalEnergy
    };
    Q_ENUM(TimeSeriesType)

    explicit DoublePendulum(
        // Physical parameters
        double m1, double m2,     // Point masses
        double rodMass1, double rodMass2,     // Rod masses (renamed from d_m1_rod, d_m2_rod)
        double l1, double l2,     // Rod lengths
        double b1, double b2,     // Linear friction coefficients
        double c1, double c2,     // Air resistance coefficients
        double g,                 // Gravity acceleration
        
        // Initial state
        double theta1_abs,        // Absolute angle of first rod from vertical
        double omega1,            // Angular velocity of first rod
        double theta2_rel,        // Relative angle of second rod from first rod's direction
        double omega2,            // Angular velocity of second rod
        
        QObject *parent = nullptr
    );

    // Public methods for simulation
    Q_INVOKABLE void step(double dt);
    Q_INVOKABLE void reset(double newTheta1_abs, double newOmega1, 
                          double newTheta2_rel, double newOmega2);
    
    // File saving method for exporting chart data
    Q_INVOKABLE bool saveTextToFile(const QString &filePath, const QString &content);
    
    // Getters for the current state
    double getTheta1() const;
    double getOmega1() const;
    double getTheta2() const;
    double getOmega2() const;
    
    // Setters for angles (for QML interaction)
    void setTheta1(double newTheta1);
    void setTheta2(double newTheta2);
    
    // Getters and setters for masses
    double getM1() const;
    double getM2() const;
    void setM1(double newM1);
    void setM2(double newM2);
    
    // Getters and setters for rod masses
    double getRodMass1() const;
    double getRodMass2() const;
    void setRodMass1(double newRodMass1);
    void setRodMass2(double newRodMass2);
    
    // Getters and setters for rod lengths
    double getL1() const;
    double getL2() const;
    void setL1(double newL1);
    void setL2(double newL2);
    
    // Getters and setters for friction coefficients
    double getB1() const;
    double getB2() const;
    void setB1(double newB1);
    void setB2(double newB2);
    
    // Getters and setters for air resistance coefficients
    double getC1() const;
    double getC2() const;
    void setC1(double newC1);
    void setC2(double newC2);
    
    // Getter and setter for gravity
    double getG() const;
    void setG(double newGValue);

    // Getter and setter for simulation speed
    double getSimulationSpeed() const;
    void setSimulationSpeed(double newSpeed);
    bool getSimulationFailed() const;

    // New methods for trace functionality
    Q_INVOKABLE QVector<QPointF> getTrace1Points() const;
    Q_INVOKABLE QVector<QPointF> getTrace2Points() const;
    Q_INVOKABLE void clearTraces();
    
    // Getters and setters for trace visibility
    bool getShowTrace1() const;
    void setShowTrace1(bool show);
    bool getShowTrace2() const;
    void setShowTrace2(bool show);

    // Methods for graph history data
    Q_INVOKABLE QVector<QPointF> getTheta1History() const;
    Q_INVOKABLE QVector<QPointF> getTheta2History() const;
    Q_INVOKABLE QVector<QPointF> getOmega1History() const;
    Q_INVOKABLE QVector<QPointF> getOmega2History() const;
    Q_INVOKABLE void clearHistory();
    
    // Methods for energy history data
    Q_INVOKABLE QVector<QPointF> getKineticEnergyHistory() const;
    Q_INVOKABLE QVector<QPointF> getPotentialEnergyHistory() const;
    Q_INVOKABLE QVector<QPointF> getTotalEnergyHistory() const;
    
    // Methods for Poincare map data
    Q_INVOKABLE QVector<QPointF> getPoincareMapPoints() const;
    Q_INVOKABLE void clearPoincareMapPoints();
    
    // New methods for incremental traces
    Q_INVOKABLE QVariantList consumeNewTrace1Points();
    Q_INVOKABLE QVariantList consumeNewTrace2Points();
    
    // New method for phase portrait data
    Q_INVOKABLE QVariantList getPhasePortraitData(
        TimeSeriesType xSeries,
        TimeSeriesType ySeries
    );
    
    // New method for processed time series data
    Q_INVOKABLE QVariantList getProcessedTimeSeriesData(
        TimeSeriesType seriesType,
        double viewPortMinTime,
        double viewPortMaxTime,
        bool rdpEnabled,
        double rdpEpsilon,
        bool limitPointsEnabled,
        int maxPointsLimit
    );

    // Getters for current energy values
    double getCurrentKineticEnergy() const;
    double getCurrentPotentialEnergy() const;
    double getCurrentTotalEnergy() const;
    
    // Getter for current simulation time
    double getCurrentTime() const;

    // Getter for bob2 Poincare flash state
    bool getBob2PoincareFlash() const;
    
    // Control flag for manual manipulation
    Q_INVOKABLE void setManualControl(bool isActive);

signals:
    void theta1Changed();
    void theta2Changed();
    void omega1Changed();
    void omega2Changed();
    void stateChanged();
    void m1Changed();
    void m2Changed();
    void rodMass1Changed();
    void rodMass2Changed();
    void l1Changed();
    void l2Changed();
    void b1Changed();
    void b2Changed();
    void c1Changed();
    void c2Changed();
    void gChanged();
    void simulationSpeedChanged();
    void simulationFailedChanged();
    void showTrace1Changed();
    void showTrace2Changed();
    void historyUpdated(); // Signal that the data for graphs has been updated
    void currentKineticEnergyChanged();
    void currentPotentialEnergyChanged();
    void currentTotalEnergyChanged();
    void currentTimeChanged();
    void bob2PoincareFlashChanged();

private Q_SLOTS:
    void resetBob2Flash();

private:
    // Physical parameters
    double m1, m2;    // Point masses at the ends of rods
    double m_rodMass1, m_rodMass2;    // Rod masses (renamed from d_m1_rod, d_m2_rod)
    double l1, l2;    // Rod lengths
    double b1, b2;    // Linear friction coefficients
    double c1, c2;    // Quadratic air resistance coefficients
    double g;         // Gravity acceleration
    double m_simulationSpeed = 1.0; // Simulation speed multiplier
    bool m_simulationFailed = false; // Simulation failure state
    bool m_isManualControlActive = false; // Flag to indicate user is dragging the pendulum
    
    // Maximum number of points to store in history and trace buffers.
    // A value of 500,000 provides a good balance between long-term
    // chart visibility and memory consumption.
    static constexpr size_t MAX_BUFFER_SIZE = 500000;
    
    // Current state
    double theta1;    // Absolute angle of the first rod from vertical
    double omega1;    // Angular velocity of the first rod
    double theta2;    // Relative angle of the second rod from the first rod's direction
    double omega2;    // Angular velocity of the second rod
    
    // Trace-related members
    QVector<QPointF> m_trace1_points;
    QVector<QPointF> m_trace2_points;
    bool m_showTrace1 = false;
    bool m_showTrace2 = false;
    
    // Graph history data
    QVector<QPointF> m_theta1History; // X = time, Y = theta1
    QVector<QPointF> m_theta2History; // X = time, Y = theta2
    QVector<QPointF> m_omega1History; // X = time, Y = omega1
    QVector<QPointF> m_omega2History; // X = time, Y = omega2
    QVector<QPointF> m_kineticEnergyHistory; // X = time, Y = T (kinetic energy)
    QVector<QPointF> m_potentialEnergyHistory; // X = time, Y = V (potential energy)
    QVector<QPointF> m_totalEnergyHistory; // X = time, Y = E (total energy)
    double m_currentTimeForHistory = 0.0; // Current simulation time for history
    double m_last_used_h = 0.001;         // Last successfully used integration step
    double m_time_accumulator = 0.0;      // Time accumulator between frames
    
    // Poincare map related
    QVector<QPointF> m_poincareMapPoints; // points of the Poincare map
    double prev_theta1_for_poincare = 0.0; // For tracking theta1 = 0 intersection
    bool m_bob2PoincareFlash = false;
    QTimer* m_bob2FlashTimer;
    
    // Current energy values
    double m_currentKineticEnergy = 0.0;
    double m_currentPotentialEnergy = 0.0;
    double m_currentTotalEnergy = 0.0;

    // New buffers for incremental trace points
    std::vector<QPointF> m_new_trace1_points;
    std::vector<QPointF> m_new_trace2_points;

    // FSAL (First Same As Last) optimization
    bool m_fsal_ready = false;
    std::vector<double> m_last_fsal_k;
    double m_last_fsal_t = 0.0;

    // Helper function to update energy values based on the current state
    void updateEnergies(const std::vector<double>& state);

    // Helper function to update trace points for the bobs
    void updateTraces(const std::vector<double>& state);

    // Helper function to calculate distance between points
    double calculateDistance(const QPointF& p1, const QPointF& p2) const;

    // Compute derivatives for the RK4 method
    std::vector<double> getDerivatives(double t, const std::vector<double>& yState) const;
    
    // Dormand-Prince parameters as constants - updated for better energy conservation
    static constexpr double DOPRI_ATOL = 1.0e-14;    // Absolute tolerance
    static constexpr double DOPRI_RTOL = 1.0e-13;    // Relative tolerance
    static constexpr double DOPRI_HMIN = 1.0e-8;     // Minimum step size
    static constexpr double DOPRI_HMAX = 0.005;      // Maximum step size, reduced for smoother plotting
    static constexpr double DOPRI_SAFETY_FACTOR = 0.9; // Safety factor for step size selection
    static constexpr double DOPRI_FAC_MIN = 0.2;      // Minimum factor for step size changes
    static constexpr double DOPRI_FAC_MAX = 5.0;      // Maximum factor for step size changes
    
    // Dormand-Prince 5(4) Butcher Tableau coefficients.
    // Using static constexpr makes them compile-time constants available to all instances.
    static constexpr double DP5_C2=1./5., DP5_C3=3./10., DP5_C4=4./5., DP5_C5=8./9., DP5_C6=1., DP5_C7=1.;

    static constexpr double DP5_A21=1./5., DP5_A31=3./40., DP5_A32=9./40.,
                            DP5_A41=44./45., DP5_A42=-56./15., DP5_A43=32./9.,
                            DP5_A51=19372./6561., DP5_A52=-25360./2187., DP5_A53=64448./6561., DP5_A54=-212./729.,
                            DP5_A61=9017./3168., DP5_A62=-355./33., DP5_A63=46732./5247., DP5_A64=49./176., DP5_A65=-5103./18656.,
                            DP5_A71=35./384., DP5_A73=500./1113., DP5_A74=125./192., DP5_A75=-2187./6784., DP5_A76=11./84.;
    
    // Coefficients for the 5th order solution (y_{n+1})
    static constexpr double DP5_B1=35./384., DP5_B2=0., DP5_B3=500./1113., DP5_B4=125./192., DP5_B5=-2187./6784., DP5_B6=11./84., DP5_B7=0.;

    // Coefficients for the 4th order embedded solution (for error estimation)
    static constexpr double DP5_E1=71./57600., DP5_E2=0., DP5_E3=-71./16695., DP5_E4=71./1920., DP5_E5=-17253./339200., DP5_E6=22./525., DP5_E7=-1./40.;
    
    // --- Simulation & Gameplay Constants ---

    // Duration of the visual flash on Poincare section crossing (in milliseconds)
    static constexpr int POINCARE_FLASH_DURATION_MS = 250;

    // Tolerance for theta1 to be considered "at the vertical" for the Poincare map
    static constexpr double POINCARE_THETA1_TOLERANCE_RAD = 0.15;
    
    // Minimum positive velocity for a valid Poincare section crossing (to avoid trivial crossings)
    static constexpr double POINCARE_OMEGA1_MIN_VELOCITY_RAD_S = 0.05;

    // Minimum physical distance between two consecutive points in a trace to be stored.
    // This prevents the trace buffer from being flooded with redundant data.
    static constexpr double MIN_TRACE_DISTANCE = 0.01;
    
    // Dormand-Prince 5(4) method for adaptive step size integration
    void performOneDormandPrinceStep(
        double tCurrent,
        const std::vector<double>& yCurrent, // Input state {th1, o1, th2, o2}
        double& hInOut,                      // Input: proposed step; Output: suggested step for next attempt/step
        std::vector<double>& yNext,          // Output: state after successful step
        bool& stepAccepted                   // Output: true if step was accepted, false otherwise
    );
};

#endif // DOUBLEPENDULUM_H
