# Виртуальная лаборатория: Двойной маятник

<p align="center">
  <img src="https://github.com/user-attachments/assets/0c048278-db8c-46be-8a54-d0a0db2a7039" alt="Скриншот приложения">
</p>

Интерактивная симуляция двойного маятника, написанная на C++ и QML с использованием фреймворка Qt. Этот проект позволяет в реальном времени исследовать сложное поведение системы, демонстрирующей детерминированный хаос, настраивать ее физические параметры и анализировать динамику с помощью встроенных графических инструментов.

## Оглавление
- [Архитектура проекта](#архитектура-проекта)
- [Структура проекта](#структура-проекта)
- [Физическая модель и вывод уравнений](#физическая-модель-и-вывод-уравнений)
- [Численный метод: Дорманд-Принс 5(4)](#численный-метод-дорманд-принс-54)
- [Технологический стек](#технологический-стек)
- [Сборка и запуск](#сборка-и-запуск)
- [Об авторе](#об-авторе)

## Архитектура проекта

Проект построен по современной архитектуре **Backend-Frontend**, которая идеально разделяет логику и представление.

### Backend (Ядро, C++)
Сердцем приложения является класс `DoublePendulum`, реализованный на C++. Он полностью инкапсулирует физическую модель и не имеет никакой информации об интерфейсе.

**Ответственность ядра:**
- **Решение системы ОДУ**: Интегрирование уравнений движения с помощью численного метода.
- **Управление состоянием**: Хранение текущих углов, скоростей и физических параметров системы.
- **Расчет производных величин**: Вычисление кинетической, потенциальной и полной энергии.
- **Хранение истории**: Ведение буферов с историей движения для построения графиков.
- **Логика карты Пуанкаре**: Детектирование пересечений заданной плоскости в фазовом пространстве.

### Frontend (Представление, QML)
Пользовательский интерфейс написан на декларативном языке QML. Он отвечает исключительно за визуализацию данных, получаемых от ядра, и передачу действий пользователя (клики, перетаскивания) в C++ часть.

### Связь (Qt Meta-Object System)
Взаимодействие между C++ и QML осуществляется через "клей" фреймворка Qt:
- **`Q_PROPERTY`**: Позволяет QML напрямую читать и изменять параметры C++ ядра (`pendulum.m1 = 1.5`).
- **Сигналы и слоты**: C++ ядро уведомляет QML об изменениях состояния (например, `stateChanged()`), а QML вызывает функции ядра (например, `pendulum.reset()`) через `Q_INVOKABLE`.

## Структура проекта

-   `CMakeLists.txt`: Корневой файл сборки проекта, который определяет зависимости, исходные файлы и правила компиляции.
-   `main.cpp`: Точка входа в приложение. Создает экземпляр `QApplication`, C++ ядро `DoublePendulum` и загружает QML-интерфейс.
-   `/include/`: Директория для всех заголовочных файлов (`.h`) C++ частей проекта.
    -   `/core/DoublePendulum.h`: Заголовочный файл для ядра симуляции.
    -   `/ui/SplashScreenHandler.h`: Заголовочный файл для обработчика экрана-заставки.
-   `/src/`: Директория с файлами реализации (`.cpp`) и QML-кодом.
    -   `/core/DoublePendulum.cpp`: Файл реализации ядра симуляции.
    -   `/ui/SplashScreenHandler.cpp`: Файл реализации обработчика экрана-заставки.
    -   `/qml/`: Директория со всеми QML-файлами интерфейса.
        -   `Main.qml`: Корневой QML-компонент, собирающий все элементы интерфейса.
        -   `SplashScreen.qml`: Экран-заставка.
        -   `PendulumCanvas2D.qml`: Компонент для 2D-визуализации маятника.
        -   `IncrementalTraceDrawer.qml`: Компонент для эффективной отрисовки следов.
        -   `ChartPlaceholder.qml`: Мощный компонент для создания всех видов графиков.
        -   `ParameterStepper.qml`: Переиспользуемый компонент для полей ввода с кнопками "+/-".
        -   `HelpPopup.qml`: Всплывающее окно с руководством пользователя.
-   `/resources/`: Директория с ресурсами приложения.
    -   `/icons/`: Иконки интерфейса в формате `.svg`.
    -   `/images/`: Растровые изображения (например, для `README`).
    -   `/models/`: 3D-модель маятника в формате `.gltf`.
    -   `resources.qrc`: Файл ресурсов Qt, который "встраивает" все ресурсы в исполняемый файл.


## Физическая модель и вывод уравнений

Для описания движения системы был выбран **формализм Лагранжа**, так как он позволяет элегантно вывести уравнения, игнорируя силы реакции связей. Лагранжиан системы определяется как разность между полной кинетической и полной потенциальной энергией.

Модель учитывает как точечные массы на концах, так и распределенные массы стержней.

### Кинетическая и потенциальная энергия

**Полная кинетическая энергия** системы:
<p align="center">
  <img src="https://github.com/user-attachments/assets/25cca925-c81b-4520-ae1a-39b08b7b41b8" alt="Формула кинетической энергии">
</p>

**Полная потенциальная энергия** системы (относительно точки подвеса):
<p align="center">
  <img src="https://github.com/user-attachments/assets/02f48483-614b-47ae-b2fa-df0f8287cf94" alt="Формула потенциальной энергии">
</p>

### Уравнения движения

Уравнения движения получаются из **уравнений Эйлера-Лагранжа** с учетом неконсервативных диссипативных сил (линейное вязкое трение и квадратичное сопротивление воздуха):
<p align="center">
  <img src="https://github.com/user-attachments/assets/9274c72f-f07b-4b88-9d58-19b2b154699a" alt="Формула уравнения Эйлера-Лагранжа">
</p>

После выполнения дифференцирования и подстановки, мы получаем систему из двух связанных нелинейных обыкновенных дифференциальных уравнений второго порядка, которая и решается численно.

**Уравнение для координаты $\theta_1$:**
<p align="center">
  <img src="https://github.com/user-attachments/assets/29bf176b-b231-40d4-b146-4650ff25795f" alt="Формула для theta_1">
</p>

**Уравнение для координаты $\theta_2$:**
<p align="center">
  <img src="https://github.com/user-attachments/assets/9a6aa1d7-453b-4cc6-a057-4ca0749d7bb6" alt="Формула для theta_2">
</p>

## Численный метод: Дорманд-Принс 5(4)

Поскольку полученная система ОДУ является нелинейной и не имеет аналитического решения, для ее интегрирования применяется численный метод **Дорманда-Принса 5(4) порядка (DOPRI5)**. Этот метод относится к семейству явных методов Рунге-Кутты и является одним из наиболее эффективных для решения нежестких систем ОДУ.

### Адаптивный шаг

Ключевое преимущество этого метода — **адаптивный шаг**. В отличие от методов с фиксированным шагом (как классический РК4), DOPRI5 на каждой итерации вычисляет два решения: одно 5-го порядка точности (основное) и одно 4-го (вложенное). Разница между этими двумя решениями используется для оценки локальной погрешности на текущем шаге.

- Если **погрешность велика** и превышает заданный допуск, шаг `h` отвергается и вычисляется заново с меньшим значением `h`.
- Если **погрешность мала**, шаг принимается, и алгоритм рассчитывает оптимальный размер `h` для следующей итерации, как правило, увеличивая его.

Это позволяет методу "сгущать" шаги на участках с быстрой, сложной динамикой (чтобы сохранить точность) и "разрежать" их на участках с плавным движением (чтобы сэкономить вычислительные ресурсы). Такой подход критически важен для моделирования хаотических систем, где малейшие ошибки быстро накапливаются.

### Реализация и FSAL-оптимизация

Алгоритм для одного шага интегрирования можно описать так:
1. Имея состояние системы $y_n$ в момент времени $t_n$, вычисляется 7 "пробных" производных (наклонов) $k_1, ..., k_7$ в различных промежуточных точках внутри шага $h$. Их коэффициенты определяются **таблицей Бутчера**.
2. На основе этих наклонов вычисляется решение 5-го порядка $y_{n+1}$ и решение 4-го порядка $y^*_{n+1}$.
3. Оценивается ошибка $E = ||y_{n+1} - y^*_{n+1}||$.
4. Если $E$ меньше допуска, шаг принимается, и вычисляется новый, оптимальный размер шага $h_{new}$.
5. Если $E$ больше допуска, шаг отвергается, и вычисление повторяется с уменьшенным шагом.

В коде также реализована **FSAL-оптимизация (First Same As Last)**. Она является свойством таблиц Бутчера для методов Дорманда-Принса и позволяет использовать последний "пробный" наклон ($k_7$) с успешного шага как первый наклон ($k_1$) для следующего. Это экономит один полный вызов самой ресурсоемкой функции (вычисления производных) на каждой итерации и даёт прирост производительности до 15-20%.

## Технологический стек

- **C++17**: Для реализации высокопроизводительного вычислительного ядра.
- **Qt 6**: Кроссплатформенный фреймворк, основа всего приложения.
- **QML**: Декларативный язык для построения пользовательского интерфейса.
- **Qt Quick 3D**: Модуль для рендеринга и управления 3D-сценой.
- **CMake**: Система сборки проекта.
- **Assimp (Open Asset Import Library)**: Библиотека для загрузки 3D-моделей в формате `gltf`.

## Сборка и запуск

Для сборки проекта вам понадобится компилятор C++, установленный Qt 6 и CMake.

1.  Клонируйте репозиторий:
    ```bash
    git clone https://github.com/darthpsl/Double-Pendulum-qt.git
    cd Double-Pendulum-qt
    ```

2.  Создайте директорию для сборки:
    ```bash
    mkdir build
    cd build
    ```

3.  Запустите CMake для генерации файлов сборки (укажите путь к вашему Qt):
    ```bash
    cmake .. -DCMAKE_PREFIX_PATH=/path/to/your/Qt/6.x.x/platform
    ```

4.  Скомпилируйте проект:
    ```bash
    cmake --build .
    ```

5.  Запустите исполняемый файл, который появится в папке `build`.

## Об авторе

Проект разработан в рамках учебной и исследовательской работы.

- **Автор:** Кудрявцев Павел Павлович
- **GitHub:** [@PalPalych5](https://github.com/PalPalych5)
- **Email:** pavlikkudryavtsev@gmail.com