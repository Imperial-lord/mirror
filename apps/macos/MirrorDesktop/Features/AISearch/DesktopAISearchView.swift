import SwiftData
import SwiftUI

struct DesktopAISearchView: View {
  @Environment(DesktopSession.self) private var session
  @Query(sort: \WatchHistoryItem.lastWatched, order: .reverse) private var history:
    [WatchHistoryItem]
  @State private var model = AISearchModel()
  @State private var saving: MovieDetail?
  @State private var actionError: String?
  @FocusState private var focused: Bool
  private let auth = AuthService.shared
  private var scope: String? {
    auth.currentUser.map { $0.uid + "." + (auth.currentProfile?.id ?? "default") }
  }
  private var watched: [Int] {
    history.filter { $0.userId == auth.currentUser?.uid && $0.isWatched }.map(\.movieId)
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("AI search").font(.system(size: 13, weight: .medium))
        Spacer()
        if !model.messages.isEmpty {
          Button("New chat") {
            model.newChat()
            focused = true
          }.buttonStyle(.plain)
            .font(.system(size: 12)).foregroundStyle(Color.mirrorTextSecondary)
        }
      }.padding(.horizontal, 38).padding(.bottom, 16)
      conversation
      composer
    }
    .background(Color.mirrorBackground)
    .task(id: scope) {
      model.load(scope: scope)
      focused = true
    }
    .onDisappear { model.cancel() }
    .sheet(item: $saving) { DesktopSaveSheet(movie: $0) }
    .alert(
      "Mirror",
      isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    ) {
      Button("OK", role: .cancel) { actionError = nil }
    } message: {
      Text(actionError ?? "")
    }
  }
  private var conversation: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 25) {
          if model.messages.isEmpty { welcome }
          ForEach(model.messages) { message in
            VStack(alignment: .leading, spacing: 14) {
              messageBubble(message)
              if !message.recommendations.isEmpty {
                LazyVGrid(
                  columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 14)],
                  alignment: .leading, spacing: 14
                ) {
                  ForEach(message.recommendations) { recommendation in
                    recommendationCard(recommendation)
                  }
                }
              }
            }
          }
          if model.searching {
            HStack(spacing: 10) {
              ProgressView().controlSize(.small)
              Text("Finding your next movie…").font(.system(size: 13)).foregroundStyle(
                Color.mirrorTextSecondary)
            }.padding(.vertical, 8).accessibilityLabel("Finding your next movie")
          }
          if let error = model.error {
            VStack(alignment: .leading, spacing: 10) {
              Text(error).font(.system(size: 13)).foregroundStyle(Color.mirrorTextSecondary)
              if model.messages.last?.role == "user", !model.searching, scope != nil {
                Button("Try again") { model.retry(excluding: watched) }.buttonStyle(.plain).font(
                  .system(size: 13, weight: .semibold))
              }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 14))
          }
          Color.clear.frame(height: 1).id("chat-bottom")
        }.frame(maxWidth: 1100).frame(maxWidth: .infinity).padding(.horizontal, 38).padding(
          .bottom, 20)
      }
      .onChange(of: model.messages.count) { _, _ in
        withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) }
      }
      .onChange(of: model.searching) { _, _ in
        withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) }
      }
      .onAppear { proxy.scrollTo("chat-bottom", anchor: .bottom) }
    }
  }
  private var welcome: some View {
    VStack(alignment: .leading, spacing: 20) {
      PhosphorView(.magicStar, size: 30, color: .mirrorTextSecondary)
        .frame(width: 64, height: 64).background(Color.mirrorSurface1, in: Circle())
      Text("What are you in the mood for?").font(.system(size: 27, weight: .semibold)).tracking(
        -0.5)
      Text("A feeling, a story, or a movie you loved. Let’s find something worth watching.")
        .font(.system(size: 14)).foregroundStyle(Color.mirrorTextSecondary).fixedSize(
          horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 9) {
        ForEach(
          [
            "Something like Interstellar, but shorter", "A clever thriller without horror",
            "A funny movie for a quiet evening",
          ], id: \.self
        ) { prompt in
          Button {
            model.draft = prompt
            focused = true
          } label: {
            HStack(spacing: 12) {
              Text(prompt).font(.system(size: 13))
              Spacer()
              PhosphorView(.arrowRight, size: 16, color: .mirrorTextSecondary)
            }.padding(15).background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 12))
              .contentShape(RoundedRectangle(cornerRadius: 12))
          }.buttonStyle(.plain)
        }
      }.frame(maxWidth: 520)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 28)
  }
  private func messageBubble(_ message: AIChatMessage) -> some View {
    let fromUser = message.role == "user"
    return VStack(alignment: .leading, spacing: 6) {
      Text(fromUser ? "You" : "Mirror").font(.system(size: 11, weight: .medium)).foregroundStyle(
        Color.mirrorTextTertiary)
      Text(message.content).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
    }.padding(16).frame(maxWidth: 720, alignment: .leading)
      .background(
        fromUser ? Color.mirrorSurface2 : .mirrorSurface1, in: RoundedRectangle(cornerRadius: 16)
      )
      .frame(maxWidth: .infinity, alignment: fromUser ? .trailing : .leading)
  }
  private func recommendationCard(_ item: AIRecommendation) -> some View {
    VStack(alignment: .leading, spacing: 13) {
      Button {
        session.open(item.id)
      } label: {
        HStack(alignment: .top, spacing: 12) {
          DesktopImage(url: item.movie.posterURL).frame(width: 72, height: 106).clipShape(
            RoundedRectangle(cornerRadius: 9))
          VStack(alignment: .leading, spacing: 6) {
            Text(item.movie.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
            Text("\(String(item.movie.year)) · \(item.movie.formattedRuntime)").font(
              .system(size: 11)
            ).foregroundStyle(Color.mirrorTextSecondary)
            Text("IMDb \(item.movie.rating, specifier: "%.1f")").font(.system(size: 11))
              .foregroundStyle(Color.mirrorTextSecondary)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.contentShape(Rectangle())
      }.buttonStyle(.plain).help("View \(item.movie.title)")
      Text(item.reason).font(.system(size: 12)).lineSpacing(3).foregroundStyle(
        Color.mirrorTextSecondary
      ).fixedSize(horizontal: false, vertical: true)
      HStack {
        Button {
          session.play(item.id)
        } label: {
          HStack(spacing: 6) {
            PhosphorView(.playBold, size: 13)
            Text("Play")
          }.font(.system(size: 12, weight: .semibold))
        }.buttonStyle(.plain)
        Spacer()
        DesktopIconButton(icon: .add, help: "Save \(item.movie.title)") {
          guard scope != nil else {
            session.showSignIn = true
            return
          }
          Task {
            do { saving = try await MovieRepository.shared.fetchMovieDetail(id: item.id) } catch {
              actionError = "Couldn’t open this movie. Please try again."
            }
          }
        }
      }
    }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 15))
      .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.mirrorInk.opacity(0.06)))
  }
  private var composer: some View {
    VStack(alignment: .leading, spacing: 11) {
      if scope == nil {
        HStack {
          Text("Sign in to find your next movie with Mirror.").font(.system(size: 13))
            .foregroundStyle(Color.mirrorTextSecondary)
          Spacer()
          DesktopAction(title: "Sign in", primary: true) { session.showSignIn = true }
        }
      }
      HStack(alignment: .center, spacing: 12) {
        TextField("Describe a movie you’d love to watch…", text: $model.draft, axis: .vertical)
          .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...4).focused($focused)
          .onSubmit { send() }.disabled(model.searching)
        Button {
          if model.searching {
            model.cancel()
            model.error = "Search stopped. You can try it again."
          } else {
            send()
          }
        } label: {
          PhosphorView(model.searching ? .close : .arrowRight, size: 19, color: .mirrorOnInk)
            .frame(width: 38, height: 38).background(Color.mirrorInk, in: Circle())
        }.buttonStyle(.plain).help(model.searching ? "Stop search" : "Send · ⌘Return")
          .accessibilityLabel(model.searching ? "Stop search" : "Send message")
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(
            !model.searching
              && (scope == nil
                || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          )
      }.padding(16).background(Color.mirrorSurface1, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.mirrorInk.opacity(0.1)))
      HStack(alignment: .top, spacing: 20) {
        Text("Messages are sent to Groq to find matches. Chat history stays on this Mac.")
          .font(.system(size: 10)).foregroundStyle(Color.mirrorTextTertiary)
        Spacer()
        Toggle("Hide watched", isOn: $model.hideWatched).toggleStyle(.checkbox)
          .font(.system(size: 11)).disabled(scope == nil || model.searching)
      }
    }.frame(maxWidth: 1100).frame(maxWidth: .infinity).padding(.horizontal, 38).padding(.bottom, 25)
      .padding(.top, 12)
  }
  private func send() {
    guard scope != nil else {
      session.showSignIn = true
      return
    }
    model.send(excluding: watched)
  }
}
