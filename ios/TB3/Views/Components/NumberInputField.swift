// TB3 iOS — Number input with custom number pad that includes Done key

import SwiftUI
import UIKit

/// A text field with a custom number pad keyboard that has a "Done" button
/// in the bottom-left empty space of the keypad.
struct NumberInputField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var width: CGFloat = 60

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.textAlignment = .right
        tf.placeholder = placeholder
        tf.font = .preferredFont(forTextStyle: .body)
        tf.textColor = .white
        tf.delegate = context.coordinator
        tf.text = text

        // Custom number pad with Done key
        let keyboard = NumberPadView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 260))
        keyboard.onKeyTap = { [weak tf] key in
            guard let tf = tf else { return }
            switch key {
            case .number(let n):
                let current = tf.text ?? ""
                let updated = current + "\(n)"
                tf.text = updated
                context.coordinator.text = updated
            case .delete:
                var current = tf.text ?? ""
                if !current.isEmpty {
                    current.removeLast()
                    tf.text = current
                    context.coordinator.text = current
                }
            case .done:
                tf.resignFirstResponder()
            }
        }
        tf.inputView = keyboard

        // Size constraint
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.widthAnchor.constraint(equalToConstant: width).isActive = true

        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        if tf.text != text {
            tf.text = text
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        // Block normal input since our custom keyboard handles it
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            text = textField.text ?? ""
        }
    }
}

// MARK: - Custom Number Pad

private enum NumberPadKey {
    case number(Int)
    case delete
    case done
}

private class NumberPadView: UIView {
    var onKeyTap: ((NumberPadKey) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)

        // 4 rows x 3 columns grid
        let keys: [[NumberPadKey?]] = [
            [.number(1), .number(2), .number(3)],
            [.number(4), .number(5), .number(6)],
            [.number(7), .number(8), .number(9)],
            [.done,      .number(0), .delete],
        ]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        for row in keys {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 6
            rowStack.distribution = .fillEqually

            for key in row {
                let button = createButton(for: key)
                rowStack.addArrangedSubview(button)
            }

            stack.addArrangedSubview(rowStack)
        }
    }

    private func createButton(for key: NumberPadKey?) -> UIButton {
        let button = UIButton(type: .custom)
        button.layer.cornerRadius = 5
        button.clipsToBounds = true

        switch key {
        case .number(let n):
            button.setTitle("\(n)", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 26, weight: .regular)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1.0)
            button.tag = n
            button.addTarget(self, action: #selector(numberTapped(_:)), for: .touchUpInside)

        case .delete:
            let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            let image = UIImage(systemName: "delete.backward", withConfiguration: config)
            button.setImage(image, for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1.0)
            button.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

            // Long press for continuous delete
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPress(_:)))
            longPress.minimumPressDuration = 0.3
            button.addGestureRecognizer(longPress)

        case .done:
            button.setTitle("Done", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            button.setTitleColor(.systemOrange, for: .normal)
            button.backgroundColor = UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1.0)
            button.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        case .none:
            button.backgroundColor = .clear
            button.isUserInteractionEnabled = false
        }

        return button
    }

    @objc private func numberTapped(_ sender: UIButton) {
        onKeyTap?(.number(sender.tag))
    }

    @objc private func deleteTapped() {
        onKeyTap?(.delete)
    }

    @objc private func deleteLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onKeyTap?(.delete)
        }
    }

    @objc private func doneTapped() {
        onKeyTap?(.done)
    }
}
