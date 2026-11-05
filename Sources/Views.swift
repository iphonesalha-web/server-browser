import SwiftUI
import WebKit

struct EditTarget: Identifiable {
    let id = UUID()
    let panel: Panel?
}

// MARK: - قائمة السيرفرات

struct ContentView: View {
    @EnvironmentObject var store: PanelStore
    @State private var editing: EditTarget?
    @State private var activeID: UUID?
    @State private var showBrowser = false

    var body: some View {
        NavigationView {
            Group {
                if store.panels.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("لا توجد سيرفرات بعد")
                            .font(.headline)
                        Text("أضف رابط لوحة التحكم مع اسم المستخدم وكلمة المرور، وسيعبّئها التطبيق لك تلقائياً.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("إضافة سيرفر") { editing = EditTarget(panel: nil) }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(32)
                } else {
                    List {
                        ForEach(store.panels) { p in
                            Button {
                                activeID = p.id
                                showBrowser = true
                            } label: {
                                PanelRow(panel: p)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.delete(p) } label: {
                                    Label("حذف", systemImage: "trash")
                                }
                                Button { editing = EditTarget(panel: p) } label: {
                                    Label("تعديل", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button { editing = EditTarget(panel: p) } label: {
                                    Label("تعديل", systemImage: "pencil")
                                }
                                Button(role: .destructive) { store.delete(p) } label: {
                                    Label("حذف", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { store.move(from: $0, to: $1) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("السيرفرات")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { editing = EditTarget(panel: nil) } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !store.panels.isEmpty { EditButton() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $editing) { target in
            PanelEditor(original: target.panel)
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .fullScreenCover(isPresented: $showBrowser) {
            BrowserView(activeID: $activeID, isPresented: $showBrowser)
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

struct PanelRow: View {
    let panel: Panel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "server.rack")
                    .foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(panel.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(panel.host)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !panel.username.isEmpty {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - إضافة / تعديل

struct PanelEditor: View {
    @EnvironmentObject var store: PanelStore
    @Environment(\.dismiss) private var dismiss
    let original: Panel?

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("السيرفر")) {
                    TextField("الاسم، مثال: NEO 4K", text: $name)
                    TextField("رابط لوحة التحكم", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Section(header: Text("بيانات الدخول"),
                        footer: Text("تُحفظ كلمة المرور مشفّرة على هذا الجهاز فقط، وتُعبّأ تلقائياً في صفحة الدخول. خانة التحقق وزر الدخول تبقى عليك.")) {
                    TextField("اسم المستخدم", text: $username)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textContentType(.username)
                        .environment(\.layoutDirection, .leftToRight)
                    HStack {
                        Group {
                            if showPassword {
                                TextField("كلمة المرور", text: $password)
                            } else {
                                SecureField("كلمة المرور", text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textContentType(.password)
                        .environment(\.layoutDirection, .leftToRight)
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(original == nil ? "سيرفر جديد" : "تعديل السيرفر")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }.disabled(!canSave)
                }
            }
            .onAppear {
                guard let o = original else { return }
                name = o.name
                url = o.url
                username = o.username
                password = Keychain.get(o.id.uuidString)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        var p = original ?? Panel(name: "", url: "", username: "")
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.url = url.trimmingCharacters(in: .whitespaces)
        p.username = username.trimmingCharacters(in: .whitespaces)
        store.upsert(p, password: password)
        dismiss()
    }
}

// MARK: - المتصفح

struct BrowserView: View {
    @EnvironmentObject var store: PanelStore
    @Binding var activeID: UUID?
    @Binding var isPresented: Bool

    var body: some View {
        if let panel = store.panel(activeID) {
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Button { isPresented = false } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    Menu {
                        ForEach(store.panels) { p in
                            Button { activeID = p.id } label: {
                                if p.id == panel.id {
                                    Label(p.name, systemImage: "checkmark")
                                } else {
                                    Text(p.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(panel.name)
                                .font(.headline)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundColor(.primary)
                    }
                    Spacer()
                    Button { WebViewPool.shared.goBack(panel.id) } label: {
                        Image(systemName: "chevron.backward")
                    }
                    Button { WebViewPool.shared.goHome(panel) } label: {
                        Image(systemName: "house")
                    }
                    Button { WebViewPool.shared.reload(panel.id) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .font(.system(size: 18, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                Divider()
                WebContainer(panel: panel)
                    .ignoresSafeArea(edges: .bottom)
            }
        } else {
            Color.clear.onAppear { isPresented = false }
        }
    }
}

struct WebContainer: UIViewRepresentable {
    let panel: Panel

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .systemBackground
        return v
    }

    func updateUIView(_ container: UIView, context: Context) {
        let wv = WebViewPool.shared.webView(for: panel)
        guard wv.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
