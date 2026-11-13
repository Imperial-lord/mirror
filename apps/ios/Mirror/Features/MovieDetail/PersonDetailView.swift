import SwiftUI
import NukeUI

public struct PersonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let person: Cast
    @State private var biography: PersonBiography?
    @State private var filmography: [Movie] = []
    @State private var isLoading = true
    @State private var isLoadingBiography = true

    public init(person: Cast) { self.person = person }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    hero(width: geometry.size.width)
                    if isLoadingBiography {
                        ProgressView().tint(Color.mirrorInk)
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .accessibilityLabel("Loading biography")
                    } else {
                        information
                    }
                    if isLoading || !filmography.isEmpty {
                        filmographySection
                    }
                    if let entity = biography?.entity {
                        Link("Biography source", destination: entity)
                            .font(.footnote)
                            .foregroundStyle(Color.mirrorTextSecondary)
                    }
                    if person.avatarURL != nil, let source = biography?.imageSource {
                        Link("Photo credits and license", destination: source)
                            .font(.footnote)
                            .foregroundStyle(Color.mirrorTextSecondary)
                    }
                }
                .padding(.bottom, FloatingTabBarView.barHeight + Spacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.mirrorBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: person.id) {
            if isLoading { await load() }
        }
        .refreshable { await load() }
    }

    private func hero(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 16) {
                if let portrait = person.avatarURL {
                    LazyImage(url: portrait) { state in
                        if let image = state.image {
                            image.resizable().scaledToFill()
                                .frame(width: width, height: min(width * 1.05, 440))
                        } else {
                            Color.mirrorSurface1
                        }
                    }
                    .frame(width: width, height: min(width * 1.05, 440))
                    .clipped()
                    .background(Color.mirrorSurface1)
                    .accessibilityHidden(true)
                } else {
                    Color.clear.frame(height: 60)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 6) {
                    Text(person.name)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Color.mirrorInk)
                        .multilineTextAlignment(.center)
                    Text([person.creditRole, person.characterName].compactMap { $0 }.joined(separator: " • "))
                        .font(.subheadline)
                        .foregroundStyle(Color.mirrorTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Spacing.md)
            }
            Button { dismiss() } label: {
                PhosphorView(.caretLeft, size: 16, color: .mirrorInk)
                    .frame(width: 44, height: 44)
                    .background(Color.mirrorSurface1.opacity(0.95), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .padding(Spacing.md)
        }
    }

    private var information: some View {
        VStack(spacing: 14) {
            if let value = biography?.birthName { infoRow("Birth name", value: value) }
            if let birth = biography?.birthDate {
                infoRow("Born", value: String(birth.prefix(10)))
            }
            if let value = biography?.birthPlace { infoRow("Birthplace", value: value) }
            infoRow("Role in project", value: person.creditRole)
            if let value = person.characterName { infoRow("Character", value: value) }
            if let imdb = person.normalizedIMDbID, let url = URL(string: "https://www.imdb.com/name/\(imdb)/") {
                HStack {
                    Text("IMDb").foregroundStyle(Color.mirrorTextSecondary)
                    Spacer()
                    Link(imdb, destination: url).foregroundStyle(Color.mirrorInk)
                }
                .font(.subheadline)
            }
        }
        .padding(Spacing.md)
        .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, Spacing.md)
    }

    private var filmographySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filmography")
                .font(.headline)
                .foregroundStyle(Color.mirrorInk)
                .padding(.horizontal, Spacing.md)

            if isLoading {
                ProgressView().tint(Color.mirrorInk)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Spacing.sm) {
                        ForEach(filmography) { movie in
                            NavigationLink(value: Route.movieDetail(movieId: movie.id)) {
                                MoviePosterCard(movie: movie)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label).foregroundStyle(Color.mirrorTextSecondary)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Color.mirrorInk).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    @MainActor
    private func load() async {
        isLoading = true
        isLoadingBiography = biography == nil
        async let bio = PeopleMetadataService.shared.biography(person)
        async let movies = PeopleMetadataService.shared.filmography(person)
        let loadedBiography = try? await bio
        guard !Task.isCancelled else { return }
        biography = loadedBiography
        isLoadingBiography = false
        let loadedFilmography = try? await movies
        guard !Task.isCancelled else { return }
        filmography = loadedFilmography ?? []
        isLoading = false
    }
}

struct CastAndCrewView: View {
    @Environment(\.dismiss) private var dismiss
    let people: [Cast]
    @State private var department = "All"

    private var departments: [String] {
        ["All"] + ["Actor", "Director", "Writer", "Producer", "Composer"].filter { job in
            people.contains { $0.creditRole == job }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { dismiss() } label: {
                    PhosphorView(.caretLeft, size: 16, color: .mirrorInk)
                        .frame(width: 44, height: 44)
                        .background(Color.mirrorSurface1, in: Circle())
                }
                .accessibilityLabel("Back")
                Text("Cast & Crew")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(departments, id: \.self) { job in
                        Button { department = job } label: {
                            Text(job == "All" ? "All" : job + "s")
                                .font(.subheadline)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .foregroundStyle(department == job ? Color.mirrorOnInk : Color.mirrorInk)
                                .background(department == job ? Color.mirrorInk : Color.mirrorSurface1, in: Capsule())
                        }
                        .accessibilityAddTraits(department == job ? .isSelected : [])
                    }
                }.padding(.horizontal, Spacing.md)
            }
            .scrollIndicators(.hidden)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(people.filter { department == "All" || $0.creditRole == department }) { person in
                        NavigationLink(value: Route.personDetail(person: person)) {
                            HStack(spacing: 14) {
                                LazyImage(url: person.avatarURL) { state in
                                    if let image = state.image {
                                        image.resizable().scaledToFill()
                                            .frame(width: 54, height: 68)
                                    } else {
                                        PhosphorView(.userFill, size: 24, color: .mirrorTextTertiary)
                                    }
                                }
                                .frame(width: 54, height: 68)
                                .background(Color.mirrorSurface2)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(person.name).font(.subheadline.weight(.medium))
                                    Text(person.characterName ?? person.creditRole)
                                        .font(.footnote).foregroundStyle(Color.mirrorTextSecondary)
                                }
                                Spacer(minLength: 0)
                                PhosphorView(.caretRight, size: 12, color: .mirrorTextTertiary)
                            }
                            .padding(12)
                            .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, FloatingTabBarView.barHeight + Spacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Color.mirrorInk)
        .background(Color.mirrorBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .buttonStyle(.plain)
    }
}
