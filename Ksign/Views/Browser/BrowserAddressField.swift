//
//  BrowserAddressField.swift
//  Ksign
//
//  Part of the in-app browser module.
//  Text field for the address bar that selects the whole address when it is
//  tapped, like in Safari.
//

import SwiftUI
import UIKit

struct BrowserAddressField: UIViewRepresentable {
	@Binding var text: String
	@Binding var isEditing: Bool
	/// Shown while the field is not being edited (e.g. just the host)
	var idleText: String
	var placeholder: String
	var onSubmit: () -> Void

	func makeUIView(context: Context) -> UITextField {
		let field = UITextField()
		field.delegate = context.coordinator
		field.placeholder = placeholder
		field.keyboardType = .webSearch
		field.autocapitalizationType = .none
		field.autocorrectionType = .no
		field.spellCheckingType = .no
		field.returnKeyType = .go
		field.clearButtonMode = .whileEditing
		field.font = UIFont.preferredFont(forTextStyle: .body)
		field.setContentHuggingPriority(.defaultLow, for: .horizontal)
		field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		field.addTarget(
			context.coordinator,
			action: #selector(Coordinator.textChanged(_:)),
			for: .editingChanged
		)
		return field
	}

	func updateUIView(_ field: UITextField, context: Context) {
		context.coordinator.parent = self

		if !field.isFirstResponder {
			let shown = idleText.isEmpty ? text : idleText
			if field.text != shown { field.text = shown }
		}
		field.placeholder = placeholder

		if isEditing, !field.isFirstResponder {
			field.becomeFirstResponder()
		} else if !isEditing, field.isFirstResponder {
			field.resignFirstResponder()
		}
	}

	/// Never wider than the space offered, however long the address is
	func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
		CGSize(
			width: proposal.width ?? 200,
			height: uiView.intrinsicContentSize.height
		)
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	final class Coordinator: NSObject, UITextFieldDelegate {
		var parent: BrowserAddressField

		init(_ parent: BrowserAddressField) {
			self.parent = parent
		}

		@objc func textChanged(_ field: UITextField) {
			parent.text = field.text ?? ""
		}

		func textFieldDidBeginEditing(_ field: UITextField) {
			// Show the full address and select all of it, so typing replaces it
			field.text = parent.text
			DispatchQueue.main.async {
				self.parent.isEditing = true
				field.selectAll(nil)
			}
		}

		func textFieldDidEndEditing(_ field: UITextField) {
			DispatchQueue.main.async {
				self.parent.isEditing = false
			}
		}

		func textFieldShouldReturn(_ field: UITextField) -> Bool {
			parent.text = field.text ?? ""
			parent.onSubmit()
			field.resignFirstResponder()
			return true
		}
	}
}
