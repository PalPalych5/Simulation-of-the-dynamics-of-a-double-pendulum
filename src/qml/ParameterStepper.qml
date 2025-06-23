import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: root
    spacing: 6

    // Свойства компонента
    property alias labelText: paramLabel.text
    property var targetObject // Ссылка на C++ объект (pendulumObj)
    property string targetProperty // Имя свойства в C++ объекте (например, "m1")
    property double currentValue // Это будет нашим внутренним значением, которое мы читаем из targetObject
    property double stepSize: 0.1
    property double minValue: -Infinity
    property double maxValue: Infinity
    property int decimals: 2 // Количество знаков после запятой для отображения
    property bool convertToDegrees: false // Если true, значение будет считаться градусами для отображения/ввода
    property int degreeDecimals: 1 // Количество знаков после запятой для градусов
    property bool isDarkTheme: false // Флаг темной темы

    // Сигнал, который будем эмитить перед изменением C++ свойств
    signal valueAboutToChange()

    onCurrentValueChanged: {
        // console.log("QML ParameterStepper (" + labelText + "): root.currentValue CHANGED to: " + currentValue +
        //             ". TextField activeFocus: " + valueEdit.activeFocus +
        //             ", TextField current text: '" + valueEdit.text + "'" +
        //             ", targetObject: " + (targetObject ? "exists" : "null") +
        //             ", targetProperty: '" + targetProperty + "'");
        var formattedValue;
        if (root.convertToDegrees) {
            formattedValue = Number(root.currentValue * 180 / Math.PI).toFixed(root.degreeDecimals);
        } else {
            formattedValue = Number(root.currentValue).toFixed(root.decimals);
        }
        
        if (!valueEdit.activeFocus || valueEdit.text !== formattedValue) {
            valueEdit.text = formattedValue;
        }
    }

    // Initialize on component completion
    Component.onCompleted: {
        if (targetObject && targetProperty) {
            currentValue = targetObject[targetProperty];
            // console.log(labelText + " initial currentValue from target:", currentValue);
        }
    }

    implicitHeight: Math.max(paramLabel.implicitHeight, valueEdit.implicitHeight, decreaseButton.implicitHeight)

    Label {
        id: paramLabel
        Layout.alignment: Qt.AlignVCenter
        font.pixelSize: 12 // Можно настроить
        color: root.isDarkTheme ? "#E0E0E0" : "#333333"
    }

    TextField {
        id: valueEdit
        Layout.preferredWidth: 70
        Layout.alignment: Qt.AlignVCenter
        text: valueEdit.activeFocus ? valueEdit.text : 
              (root.convertToDegrees ? Number(root.currentValue * 180 / Math.PI).toFixed(root.degreeDecimals) : Number(root.currentValue).toFixed(root.decimals))
        horizontalAlignment: Text.AlignRight
        selectByMouse: true
        font.pixelSize: 12
        color: root.isDarkTheme ? "#E0E0E0" : "#333333"
        
        // Заменяем background на palette для лучшей интеграции со стилем
        palette.text: root.isDarkTheme ? "#E0E0E0" : "#333333"
        palette.base: root.isDarkTheme ? "#2D2D2D" : "#FFFFFF" // Более темный фон для темной темы
        palette.highlight: root.isDarkTheme ? Qt.lighter("#0078d7", 1.3) : "#0078d7" // Цвет выделения
        palette.highlightedText: root.isDarkTheme ? "black" : "white"

        onTextChanged: {
            // console.log("QML ParameterStepper (" + root.labelText + "): TextField text CHANGED to: '" + text + "'");
        }

        // Убираем или сильно ослабляем валидатор, если обрезка полностью на C++
        validator: DoubleValidator {
            decimals: root.decimals
            notation: DoubleValidator.StandardNotation
            locale: "C"
        }

        // Вместо onEditingFinished используем onAccepted (Enter) и onFocusChanged
        // чтобы было более предсказуемо.
        onAccepted: {
            var textValue = text.replace(",", ".");
            var parsedValue = parseFloat(textValue);
            // console.log("QML ParameterStepper (" + root.labelText + "): TextField accepted with parsedValue:", parsedValue);
            if (!isNaN(parsedValue)) {
                var valueToSend = root.convertToDegrees ? (parsedValue * Math.PI / 180) : parsedValue; // Конвертируем обратно в радианы, если нужно
                
                if (targetObject && targetProperty) {
                    // Эмитим сигнал о предстоящем изменении
                    root.valueAboutToChange();
                    
                    // Для привязанных степперов: отправляем значение в C++.
                    // C++ выполнит обрезку и через NOTIFY обновит root.currentValue.
                    // console.log("QML ParameterStepper (" + root.labelText + "): Setting C++ property", targetProperty, "to", valueToSend);
                    targetObject[targetProperty] = valueToSend;
                } else {
                    // Эмитим сигнал о предстоящем изменении
                    root.valueAboutToChange();
                    
                    // Для standalone степперов (начальные условия): обрезаем здесь и обновляем currentValue.
                    var clampedValue = Math.max(root.minValue, Math.min(root.maxValue, valueToSend));
                    if (root.currentValue !== clampedValue) {
                        root.currentValue = clampedValue;
                    }
                }
            }
        }
    }

    Button {
        id: decreaseButton
        text: "-"
        font.pixelSize: 12
        Layout.preferredWidth: 30 // Можно настроить
        Layout.preferredHeight: valueEdit.height
        Layout.alignment: Qt.AlignVCenter
        
        contentItem: Text {
            text: parent.text
            font: parent.font
            color: root.isDarkTheme ? "#E0E0E0" : "#333333"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        
        background: Rectangle {
            radius: 3
            color: parent.down ? (root.isDarkTheme ? "#404040" : "#C0C0C0") : (parent.hovered ? (root.isDarkTheme ? "#585858" : "#E0E0E0") : (root.isDarkTheme ? "#4F4F4F" : "#F0F0F0"))
            border.color: root.isDarkTheme ? "#606060" : "#B0B0B0"
            border.width: 1
        }
        
        onClicked: {
            var newValue = Number((root.currentValue - root.stepSize).toFixed(root.decimals + 2));
            newValue = Math.max(root.minValue, Math.min(root.maxValue, newValue));
            // console.log("QML ParameterStepper (" + root.labelText + "): Decrease button clicked. New value:", newValue);

            if (targetObject && targetProperty) {
                // Эмитим сигнал о предстоящем изменении
                root.valueAboutToChange();
                
                // Для привязанных степперов: всегда пытаемся установить значение в C++
                // console.log("QML ParameterStepper (" + root.labelText + "): Setting C++ property", targetProperty, "to", newValue);
                targetObject[targetProperty] = newValue;
            } else {
                // Эмитим сигнал о предстоящем изменении
                root.valueAboutToChange();
                
                // Для standalone степперов (начальные условия): обновляем только currentValue
                if (root.currentValue !== newValue) {
                    root.currentValue = newValue;
                }
            }
        }
    }

    Button {
        id: increaseButton
        text: "+"
        font.pixelSize: 12
        Layout.preferredWidth: 30 // Можно настроить
        Layout.preferredHeight: valueEdit.height
        Layout.alignment: Qt.AlignVCenter
        
        contentItem: Text {
            text: parent.text
            font: parent.font
            color: root.isDarkTheme ? "#E0E0E0" : "#333333"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        
        background: Rectangle {
            radius: 3
            color: parent.down ? (root.isDarkTheme ? "#404040" : "#C0C0C0") : (parent.hovered ? (root.isDarkTheme ? "#585858" : "#E0E0E0") : (root.isDarkTheme ? "#4F4F4F" : "#F0F0F0"))
            border.color: root.isDarkTheme ? "#606060" : "#B0B0B0"
            border.width: 1
        }
        
        onClicked: {
            var newValue = Number((root.currentValue + root.stepSize).toFixed(root.decimals + 2));
            newValue = Math.max(root.minValue, Math.min(root.maxValue, newValue));
            // console.log("QML ParameterStepper (" + root.labelText + "): Increase button clicked. New value:", newValue);

            if (targetObject && targetProperty) {
                // Эмитим сигнал о предстоящем изменении
                root.valueAboutToChange();
                
                // Для привязанных степперов: всегда пытаемся установить значение в C++
                // console.log("QML ParameterStepper (" + root.labelText + "): Setting C++ property", targetProperty, "to", newValue);
                targetObject[targetProperty] = newValue;
            } else {
                // Эмитим сигнал о предстоящем изменении
                root.valueAboutToChange();
                
                // Для standalone степперов (начальные условия): обновляем только currentValue
                if (root.currentValue !== newValue) {
                    root.currentValue = newValue;
                }
            }
        }
    }
} 