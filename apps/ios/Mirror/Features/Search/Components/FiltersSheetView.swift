import SwiftUI
import UIKit

public struct FiltersSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding public var selectedGenre: String?
    @Binding public var minimumRating: Int
    @Binding public var sortBy: String
    @Binding public var selectedCountry: String?
    @Binding public var selectedStudio: String?
    @Binding public var selectedYear: Int?
    public var onApply: (() -> Void)?

    @State private var currentRating: Double = 0
    @State private var selectedSort: String = "like_count"
    @State private var selectedGenreState: String = "All"

    @State private var countryState: String?
    @State private var studioState: String?
    @State private var yearState: Int?

    private let sortOptions = [
        ("Newest", "date_added"),
        ("Popular", "like_count"),
        ("Rating", "rating")
    ]

    public init(
        selectedGenre: Binding<String?>,
        minimumRating: Binding<Int>,
        sortBy: Binding<String>,
        selectedCountry: Binding<String?>,
        selectedStudio: Binding<String?>,
        selectedYear: Binding<Int?>,
        onApply: (() -> Void)? = nil
    ) {
        self._selectedGenre = selectedGenre
        self._minimumRating = minimumRating
        self._sortBy = sortBy
        self._selectedCountry = selectedCountry
        self._selectedStudio = selectedStudio
        self._selectedYear = selectedYear
        self.onApply = onApply
    }

    public var body: some View {
        ZStack {
            Color(mirrorHex: "060606").ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        PhosphorView(.caretLeft, size: 16)
                            .foregroundColor(Color.mirrorInk)
                            .frame(width: 44, height: 44)
                            .background(Color.mirrorInk.opacity(0.06), in: Circle())
                    }
                    .accessibilityLabel("Close filters")

                    Spacer()

                    Text("Filters")
                        .font(.mirrorH3)
                        .foregroundColor(Color.mirrorInk)

                    Spacer()

                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xl)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(spacing: 8) {
                            Menu {
                                ForEach(Genre.allCases.map(\.rawValue), id: \.self) { genre in
                                    Button {
                                        selectedGenreState = genre
                                    } label: {
                                        if selectedGenreState == genre { Label { Text(genre) } icon: { PhosphorView(.check, size: 14) } }
                                        else { Text(genre) }
                                    }
                                }
                            } label: {
                                filterRowContent(title: "Genre", value: selectedGenreState)
                            }
                            productionMenu(title: "Country", options: CatalogFilterOption.countries, selection: $countryState)
                            productionMenu(title: "Studio", options: CatalogFilterOption.studios, selection: $studioState)
                            Menu {
                                Button("All years") { yearState = nil }
                                ForEach(Array((1888...Calendar.current.component(.year, from: Date())).reversed()), id: \.self) { year in
                                    Button(String(year)) { yearState = year }
                                }
                            } label: {
                                filterRowContent(title: "Year", value: yearState.map(String.init) ?? "All")
                            }

                        }

                        // Minimum IMDb rating supported by YTS (0...9).

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Rating")
                                    .font(.mirrorBodySmall)
                                    .foregroundColor(Color.mirrorInk.opacity(0.60))
                                Spacer()
                                Text(currentRating == 0 ? "Any rating" : "From \(Int(currentRating)) to 10")
                                    .font(.mirrorBodySmall)
                                    .foregroundColor(Color.mirrorInk)
                            }

                            RatingSlider(value: $currentRating)
                                .frame(height: 32)
                            HStack {
                                Text("0")
                                Spacer()
                                Text("9+")
                            }
                            .font(.mirrorCaptionSmall)
                            .foregroundStyle(Color.mirrorTextTertiary)
                            .accessibilityHidden(true)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 12)
                        .background(Color(mirrorHex: "121214"))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // 4. Sort By Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sort by")
                                .font(.mirrorCaption)
                                .foregroundColor(Color.mirrorInk.opacity(0.40))

                            VStack(spacing: 8) {
                                ForEach(sortOptions, id: \.1) { label, value in
                                    Button(action: {
                                        HapticManager.shared.selection()
                                        selectedSort = value
                                    }) {
                                        HStack {
                                            Text(label)
                                                .font(.mirrorBodySmall)
                                                .foregroundColor(Color.mirrorInk)
                                            Spacer()
                                            ZStack {
                                                Circle()
                                                    .stroke(selectedSort == value ? Color.mirrorInk : Color.mirrorInk.opacity(0.30), lineWidth: 1.5)
                                                    .frame(width: 18, height: 18)
                                                if selectedSort == value {
                                                    Circle()
                                                        .fill(Color.mirrorInk)
                                                        .frame(width: 8, height: 8)
                                                }
                                            }
                                        }
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                    }
                                    .accessibilityAddTraits(selectedSort == value ? .isSelected : [])
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 12)
                        .background(Color(mirrorHex: "121214"))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 24)
                }

                // Bottom Action Buttons
                HStack(spacing: Spacing.md) {
                    // Reset Button
                    Button(action: {
                        HapticManager.shared.impact(.light)
                        selectedGenreState = "All"
                        currentRating = 0
                        selectedSort = "like_count"
                        countryState = nil
                        studioState = nil
                        yearState = nil
                    }) {
                        Text("Reset")
                            .font(.mirrorButton)
                            .foregroundColor(Color.mirrorInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.mirrorInk.opacity(0.10))
                            .clipShape(Capsule())
                    }

                    // Apply Button
                    Button(action: {
                        HapticManager.shared.impact(.light)
                        selectedGenre = selectedGenreState == "All" ? nil : selectedGenreState
                        minimumRating = Int(currentRating)
                        sortBy = selectedSort
                        selectedCountry = countryState
                        selectedStudio = studioState
                        selectedYear = yearState
                        onApply?()
                        dismiss()
                    }) {
                        Text("Apply")
                            .font(.mirrorButton)
                            .foregroundColor(Color.mirrorOnInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.mirrorInk)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
                .background(Color(mirrorHex: "060606"))
            }
        }
        .tint(Color.mirrorInk)
        .buttonStyle(.plain)

        .onAppear {
            currentRating = Double(minimumRating)
            selectedSort = sortBy
            selectedGenreState = selectedGenre ?? "All"
            countryState = selectedCountry
            studioState = selectedStudio
            yearState = selectedYear
        }
    }

    private func productionMenu(title: String, options: [CatalogFilterOption], selection: Binding<String?>) -> some View {
        Menu {
            Button("All") { selection.wrappedValue = nil }
            ForEach(options) { option in
                Button(option.name) { selection.wrappedValue = option.id }
            }
        } label: {
            filterRowContent(title: title, value: options.first { $0.id == selection.wrappedValue }?.name ?? "All")
        }
    }

    private func filterRowContent(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 14)).foregroundStyle(Color.mirrorInk)
            Spacer()
            Text(value).font(.system(size: 13)).foregroundStyle(Color.mirrorTextTertiary)
            PhosphorView(.caretRight, size: 14)
                .foregroundStyle(Color.mirrorTextTertiary)
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: 56)
        .background(Color(mirrorHex: "121214"), in: RoundedRectangle(cornerRadius: 10))
    }
}

// A fixed circular thumb preserves the design on iOS 26's updated slider style.
private struct RatingSlider: UIViewRepresentable {
    @Binding var value: Double
    @Environment(\.colorScheme) private var scheme

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 9
        slider.accessibilityLabel = "Minimum rating"
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        let ink: UIColor = scheme == .dark ? .white : .black
        slider.minimumTrackTintColor = ink
        slider.maximumTrackTintColor = ink.withAlphaComponent(0.14)
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            ink.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        slider.setThumbImage(thumb, for: .normal)
        slider.setThumbImage(thumb, for: .highlighted)

        context.coordinator.parent = self
        slider.value = Float(value)
        slider.accessibilityValue = value == 0 ? "Any rating" : "\(Int(value)) out of 10 or higher"
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject {
        var parent: RatingSlider
        init(parent: RatingSlider) { self.parent = parent }
        @objc func changed(_ slider: UISlider) {
            let rating = Double(slider.value.rounded())
            if rating != parent.value {
                parent.value = rating
                HapticManager.shared.selection()
            }
        }
    }
}
