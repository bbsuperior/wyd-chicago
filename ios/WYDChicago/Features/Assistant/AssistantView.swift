import SwiftUI

// MARK: - AssistantView — the AI chat (animated, multi-bubble, texting style)

struct AssistantView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AssistantViewModel()
    @State private var didLoad = false
    @State private var showMemory = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                VStack(spacing: 0) {
                    transcript
                    inputBar
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { titleView }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundColor(.wydMuted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showMemory = true
                        } label: { Label("What it remembers", systemImage: "brain") }
                        Button(role: .destructive) {
                            vm.clearMemory()
                        } label: { Label("Clear memory", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundColor(.wydText)
                    }
                }
            }
            .sheet(isPresented: $showMemory) { MemorySheet(memory: vm.memory) }
        }
        .preferredColorScheme(.dark)
        .task {
            guard !didLoad else { return }
            didLoad = true
            vm.bind(appState.backend)
            vm.greet()
        }
    }

    // MARK: Title

    private var titleView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(LinearGradient.cityNight).frame(width: 30, height: 30)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("WYD AI").font(WYDFont.displaySemibold(16)).foregroundColor(.wydText)
                Text(vm.usingLiveAI ? "online" : "demo mode")
                    .font(WYDFont.bodyMedium(11))
                    .foregroundColor(vm.usingLiveAI ? .wydSuccess : .wydMuted)
            }
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(vm.messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    if vm.isTyping {
                        TypingBubble()
                            .id("typing")
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomLeading)))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) { _ in scrollToEnd(proxy) }
            .onChange(of: vm.isTyping) { _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(WYDMotion.smooth) {
            if vm.isTyping {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = vm.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("message wyd ai…", text: $vm.input, axis: .vertical)
                    .font(WYDFont.body(16))
                    .foregroundColor(.wydText)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await vm.send() } }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color.wydSurface2))
            .overlay(Capsule().stroke(Color.wydBorder, lineWidth: 1))

            Button {
                Task { await vm.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LinearGradient.cityNight))
            }
            .buttonStyle(.pressable)
            .disabled(vm.input.trimmingCharacters(in: .whitespaces).isEmpty || vm.isTyping)
            .opacity(vm.input.trimmingCharacters(in: .whitespaces).isEmpty || vm.isTyping ? 0.5 : 1)
            .wydPrimaryGlow()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Chat bubble

private struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 40) } else { aiAvatar }

            Text(message.text)
                .font(WYDFont.body(16))
                .foregroundColor(isUser ? .white : .wydText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground)
                .clipShape(wydBubbleShape(isUser: isUser))

            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder private var bubbleBackground: some View {
        if isUser {
            LinearGradient.cityNight
        } else {
            Color.wydSurface2
        }
    }

    private var aiAvatar: some View {
        ZStack {
            Circle().fill(LinearGradient.cityNight)
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Typing indicator bubble

private struct TypingBubble: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle().fill(LinearGradient.cityNight)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 26, height: 26)

            TypingDots()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.wydSurface2)
                .clipShape(wydBubbleShape(isUser: false))

            Spacer(minLength: 40)
        }
    }
}

private struct TypingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.wydMuted)
                    .frame(width: 7, height: 7)
                    .scaleEffect(scale(for: i))
                    .opacity(0.5 + 0.5 * scale(for: i))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }

    private func scale(for i: Int) -> CGFloat {
        let t = (phase + Double(i) * 0.33).truncatingRemainder(dividingBy: 1.0)
        return 0.6 + 0.4 * (1 - abs(t - 0.5) * 2)
    }
}

// MARK: - Asymmetric chat bubble shape

private func wydBubbleShape(isUser: Bool) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
        topLeadingRadius: 18,
        bottomLeadingRadius: isUser ? 18 : 5,
        bottomTrailingRadius: isUser ? 5 : 18,
        topTrailingRadius: 18,
        style: .continuous
    )
}

// MARK: - Memory sheet

private struct MemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let memory: MemoryStore
    @State private var items: [MemoryStore.Item] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stuff WYD AI remembers about you, saved on this phone only.")
                        .font(WYDFont.body(14)).foregroundColor(.wydMuted)
                        .padding(.bottom, 4)

                    if items.isEmpty {
                        EmptyStateView(emoji: "🧠", title: "Nothing saved yet",
                                       subtitle: "Chat a bit and the assistant will start remembering your vibe.")
                    } else {
                        ForEach(items) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill").foregroundColor(.wydBrand)
                                Text(item.text).font(WYDFont.body(15)).foregroundColor(.wydText)
                                Spacer()
                            }
                            .padding(12)
                            .wydCardBackground(.wydSurface2)
                        }
                    }
                }
                .padding(16)
            }
            .background(WYDBackground())
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.wydBrand)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { items = memory.items }
    }
}

#Preview("Assistant") {
    AssistantView()
        .environmentObject(AppState(backend: MockBackend()))
        .preferredColorScheme(.dark)
}
