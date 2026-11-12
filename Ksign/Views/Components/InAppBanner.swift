//
//  InAppBanner.swift
//  Ksign
//
//  Short banner at the top of the app for finished downloads and imports,
//  shown while the Library tab is not on screen.
//

import SwiftUI

struct InAppBannerItem: Identifiable, Equatable {
	enum Kind { case download, imported, failure }

	let id = UUID()
	let kind: Kind
	let title: String
	let detail: String

	var icon: String {
		switch kind {
		case .download: return "arrow.down.circle.fill"
		case .imported: return "checkmark.circle.fill"
		case .failure: return "exclamationmark.triangle.fill"
		}
	}

	var color: Color {
		kind == .failure ? .orange : .green
	}
}

final class InAppBanner: ObservableObject {
	static let shared = InAppBanner()

	@Published private(set) var items: [InAppBannerItem] = []
	/// Set by the Library tab: nothing is shown while it is visible
	var isLibraryVisible = false

	private let _maxItems = 3

	func show(_ kind: InAppBannerItem.Kind, title: String, detail: String) {
		DispatchQueue.main.async {
			guard !self.isLibraryVisible else { return }
			let item = InAppBannerItem(kind: kind, title: title, detail: detail)
			self.items.append(item)
			if self.items.count > self._maxItems {
				self.items.removeFirst(self.items.count - self._maxItems)
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
				self?.dismiss(item)
			}
		}
	}

	func dismiss(_ item: InAppBannerItem) {
		items.removeAll { $0.id == item.id }
	}
}

struct InAppBannerOverlay: View {
	@ObservedObject var banner: InAppBanner

	var body: some View {
		VStack(spacing: 8) {
			ForEach(banner.items) { item in
				HStack(spacing: 12) {
					Image(systemName: item.icon)
						.font(.title3)
						.foregroundStyle(item.color)
					VStack(alignment: .leading, spacing: 2) {
						Text(item.title)
							.font(.subheadline.weight(.semibold))
						Text(item.detail)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.truncationMode(.middle)
					}
					Spacer(minLength: 0)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
				.browserGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
				.padding(.horizontal, 16)
				.onTapGesture { banner.dismiss(item) }
				.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(.spring(response: 0.4, dampingFraction: 0.85), value: banner.items)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.allowsHitTesting(!banner.items.isEmpty)
	}
}
