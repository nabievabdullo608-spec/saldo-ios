import SwiftUI

// MARK: - Модели данных
enum DebtType: String, Codable, CaseIterable {
    case give = "give" // Мне должен
    case take = "take" // Я должен
    
    var title: String {
        switch self {
        case .give: return "Мне должен"
        case .take: return "Я должен"
        }
    }
}

struct DebtItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var amount: Double
    var type: DebtType
    var isArchived: Bool = false
    var createdAt: Date = Date()
}

struct HistoryItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var debtId: UUID
    var name: String
    var text: String
    var date: Date = Date()
}

// MARK: - Хранилище данных (Менеджер приложения)
class DebtStore: ObservableObject {
    @Published var debts: [DebtItem] = [] {
        didSet { saveDebts() }
    }
    @Published var history: [HistoryItem] = [] {
        didSet { saveHistory() }
    }
    @Published var currency: String = "TJS" {
        didSet { UserDefaults.standard.set(currency, forKey: "app_currency") }
    }
    
    private let debtsKey = "saved_debts_v1"
    private let historyKey = "saved_history_v1"
    
    init() {
        self.currency = UserDefaults.standard.string(forKey: "app_currency") ?? "TJS"
        loadData()
    }
    
    func loadData() {
        if let data = UserDefaults.standard.data(forKey: debtsKey),
           let decoded = try? JSONDecoder().decode([DebtItem].self, from: data) {
            self.debts = decoded
        }
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            self.history = decoded
        }
    }
    
    private func saveDebts() {
        if let encoded = try? JSONEncoder().encode(debts) {
            UserDefaults.standard.set(encoded, forKey: debtsKey)
        }
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }
    
    func addDebt(name: String, amount: Double, type: DebtType) {
        let newDebt = DebtItem(name: name, amount: amount, type: type)
        debts.insert(newDebt, at: 0)
        
        let record = HistoryItem(
            debtId: newDebt.id,
            name: name,
            text: "Создан контакт: \(name) — \(Int(amount)) \(currency) (\(type.title))"
        )
        history.insert(record, at: 0)
    }
    
    func applyOperation(to debt: DebtItem, amount: Double, isDecrease: Bool) {
        guard let index = debts.firstIndex(where: { $0.id == debt.id }) else { return }
        
        var currentSigned = (debts[index].type == .give) ? debts[index].amount : -debts[index].amount
        let oldType = debts[index].type
        
        if isDecrease {
            if debts[index].type == .give {
                currentSigned -= amount
            } else {
                currentSigned += amount
            }
        } else {
            if debts[index].type == .give {
                currentSigned += amount
            } else {
                currentSigned -= amount
            }
        }
        
        if currentSigned > 0 {
            debts[index].type = .give
            debts[index].amount = currentSigned
        } else if currentSigned < 0 {
            debts[index].type = .take
            debts[index].amount = abs(currentSigned)
        } else {
            debts[index].amount = 0
            debts[index].isArchived = true
        }
        
        let actionStr = isDecrease ? "Списано -\(Int(amount))" : "Добавлено +\(Int(amount))"
        let statusNotice = (oldType != debts[index].type && debts[index].amount > 0) ? " [Статус: \(debts[index].type.title)]" : ""
        
        let log = HistoryItem(
            debtId: debt.id,
            name: debt.name,
            text: "\(debt.name): \(actionStr) \(currency)\(statusNotice)"
        )
        history.insert(log, at: 0)
    }
    
    func toggleArchive(for debt: DebtItem) {
        if let index = debts.firstIndex(where: { $0.id == debt.id }) {
            debts[index].isArchived.toggle()
        }
    }
    
    func deleteDebt(_ debt: DebtItem) {
        debts.removeAll(where: { $0.id == debt.id })
    }
    
    func clearAll() {
        debts.removeAll()
        history.removeAll()
    }
    
    var totalGive: Double {
        debts.filter { !$0.isArchived && $0.type == .give }.reduce(0) { $0 + $1.amount }
    }
    
    var totalTake: Double {
        debts.filter { !$0.isArchived && $0.type == .take }.reduce(0) { $0 + $1.amount }
    }
}

// MARK: - Главное приложение
@main
struct SaldoApp: App {
    @StateObject private var store = DebtStore()
    
    var body: some Scene {
        WindowGroup {
            MainContainerView()
                .environmentObject(store)
        }
    }
}

// MARK: - Главный контейнер с вкладками
struct MainContainerView: View {
    @EnvironmentObject var store: DebtStore
    @State private var selectedTab = 0
    @State private var showAddModal = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                DebtsListView(showAddModal: $showAddModal)
                    .tag(0)
                
                HistoryListView()
                    .tag(1)
                
                ArchiveListView()
                    .tag(2)
                
                SettingsListView()
                    .tag(3)
            }
            
            // Нативный плавающий Dock в стиле iOS
            CustomTabBar(selectedTab: $selectedTab, onAddTap: {
                showAddModal = true
            })
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showAddModal) {
            AddContactSheet()
        }
    }
}

// MARK: - Кастомный плавающий Dock с кнопкой «+»
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var onAddTap: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: "Долги", systemImage: "creditcard", tabIndex: 0)
            tabButton(title: "История", systemImage: "clock", tabIndex: 1)
            
            // Центральная круглая кнопка «+»
            Button(action: onAddTap) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(color: Color.blue.opacity(0.4), radius: 6, x: 0, y: 3)
            }
            .padding(.horizontal, 8)
            
            tabButton(title: "Архив", systemImage: "archivebox", tabIndex: 2)
            tabButton(title: "Опции", systemImage: "gearshape", tabIndex: 3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 15, x: 0, y: 8)
        )
    }
    
    private func tabButton(title: String, systemImage: String, tabIndex: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selectedTab = tabIndex
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: selectedTab == tabIndex ? .bold : .medium))
                Text(title)
                    .font(.system(size: 10, weight: selectedTab == tabIndex ? .bold : .medium))
            }
            .foregroundColor(selectedTab == tabIndex ? .blue : .black)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Экран «Долги»
struct DebtsListView: View {
    @EnvironmentObject var store: DebtStore
    @Binding var showAddModal: Bool
    
    @State private var filter: String = "all"
    @State private var searchText: String = ""
    @State private var selectedDebt: DebtItem? = nil
    
    var filteredDebts: [DebtItem] {
        store.debts.filter { debt in
            guard !debt.isArchived else { return false }
            let matchesFilter = (filter == "all") || (filter == "give" && debt.type == .give) || (filter == "take" && debt.type == .take)
            let matchesSearch = searchText.isEmpty || debt.name.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    // Карточки баланса
                    HStack(spacing: 10) {
                        SummaryCard(title: "Мне должны", amount: store.totalGive, currency: store.currency)
                        SummaryCard(title: "Я должен", amount: store.totalTake, currency: store.currency)
                    }
                    
                    // Поиск
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Поиск по имени...", text: $searchText)
                    }
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.15), lineWidth: 1.5))
                    
                    // Сегментированный фильтр
                    Picker("", selection: $filter) {
                        Text("Все").tag("all")
                        Text("Мне должен").tag("give")
                        Text("Я должен").tag("take")
                    }
                    .pickerStyle(.segmented)
                    
                    // Список контактов
                    if filteredDebts.isEmpty {
                        Text("Список контактов пуст")
                            .foregroundColor(.gray)
                            .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredDebts) { debt in
                                DebtRowView(debt: debt, currency: store.currency)
                                    .onTapGesture {
                                        selectedDebt = debt
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Мои долги")
            .sheet(item: $selectedDebt) { debt in
                ContactDetailSheet(debt: debt)
            }
        }
    }
}

// MARK: - Вид строки контакта с первой буквой
struct DebtRowView: View {
    let debt: DebtItem
    let currency: String
    
    var firstLetter: String {
        guard let first = debt.name.first else { return "?" }
        return String(first).uppercased()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Кружок с первой буквой имени
            Text(firstLetter)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.blue)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 3) {
                Text(debt.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
                Text(debt.type.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(debt.type == .give ? "+" : "-")\(Int(debt.amount)) \(currency)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                Text("Нажмите для меню ›")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue.opacity(0.12), lineWidth: 1.5))
    }
}

// MARK: - Окно контакта с анимацией на 3 сек, двумя стрелками и выпиской
struct ContactDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DebtStore
    let debt: DebtItem
    
    @State private var displayAmount: Int = 0
    @State private var showAmountSheet = false
    @State private var isDecrease = true
    @State private var showShareSheet = false
    @State private var showDatePicker = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    
    var currentDebt: DebtItem {
        store.debts.first(where: { $0.id == debt.id }) ?? debt
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                // Аватар
                Text(String(currentDebt.name.prefix(1)).uppercased())
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .padding(.top, 10)
                
                Text(currentDebt.name)
                    .font(.title2.bold())
                    .foregroundColor(.black)
                
                Text(currentDebt.type.title)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                // Анимированное табло баланса на 3 секунды
                VStack {
                    Text("\(displayAmount) \(store.currency)")
                        .font(.system(size: 32, weight: .heavy, design: .monospaced))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(16)
                
                // Две большие кнопки: Красная ВНИЗ и Зелёная ВВЕРХ
                HStack(spacing: 12) {
                    Button(action: {
                        isDecrease = true
                        showAmountSheet = true
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 22, weight: .bold))
                            Text("Уменьшить долг")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.red)
                        .cornerRadius(18)
                    }
                    
                    Button(action: {
                        isDecrease = false
                        showAmountSheet = true
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 22, weight: .bold))
                            Text("Увеличить долг")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.green)
                        .cornerRadius(18)
                    }
                }
                
                // Кнопки истории и архива
                VStack(spacing: 10) {
                    Button(action: {
                        showShareSheet = true
                    }) {
                        Label("Поделиться историей (PDF / Текст)", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue, lineWidth: 1.5))
                    }
                    
                    Button(action: {
                        store.toggleArchive(for: currentDebt)
                        dismiss()
                    }) {
                        Text(currentDebt.isArchived ? "Вернуть на главный экран" : "Перенести в Архив (VIP)")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .onAppear {
                animateCounter(target: Int(currentDebt.amount))
            }
            .sheet(isPresented: $showAmountSheet) {
                AmountInputSheet(targetDebt: currentDebt, isDecrease: isDecrease, onComplete: {
                    animateCounter(target: Int(currentDebt.amount))
                })
            }
            .confirmationDialog("Поделиться историей", isPresented: $showShareSheet, titleVisibility: .visible) {
                Button("Отправить всю историю") {
                    shareText(buildHistoryText(for: currentDebt, filtered: false))
                }
                Button("Выбрать дату / период") {
                    showDatePicker = true
                }
                Button("Отмена", role: .cancel) {}
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerFilterSheet(onApply: { start, end in
                    shareText(buildFilteredHistoryText(for: currentDebt, from: start, to: end))
                })
            }
        }
    }
    
    // Анимация бегущих цифр ровно 3 секунды
    func animateCounter(target: Int) {
        displayAmount = max(0, target - 100)
        let totalSteps = 60
        let stepDuration = 3.0 / Double(totalSteps) // 3 секунды
        var step = 0
        
        Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { timer in
            step += 1
            let progress = Double(step) / Double(totalSteps)
            let easeOut = 1 - pow(2, -10 * progress)
            displayAmount = Int(Double(target - 100) + Double(100) * easeOut)
            
            if step >= totalSteps {
                displayAmount = target
                timer.invalidate()
            }
        }
    }
    
    func buildHistoryText(for item: DebtItem, filtered: Bool) -> String {
        let logs = store.history.filter { $0.debtId == item.id || $0.name.lowercased() == item.name.lowercased() }
        var result = "Выписка долгов: \(item.name)\nТекущий баланс: \(Int(item.amount)) \(store.currency) (\(item.type.title))\n\n"
        for log in logs {
            let df = DateFormatter()
            df.dateFormat = "dd.MM.yyyy HH:mm"
            result += "\(df.string(from: log.date)) — \(log.text)\n"
        }
        return result
    }
    
    func buildFilteredHistoryText(for item: DebtItem, from: Date, to: Date) -> String {
        let logs = store.history.filter {
            ($0.debtId == item.id || $0.name.lowercased() == item.name.lowercased()) &&
            $0.date >= from && $0.date <= to
        }
        var result = "Выписка долгов: \(item.name)\nПериод: с \(from.formatted(date: .numeric, time: .omitted)) по \(to.formatted(date: .numeric, time: .omitted))\n\n"
        for log in logs {
            let df = DateFormatter()
            df.dateFormat = "dd.MM.yyyy HH:mm"
            result += "\(df.string(from: log.date)) — \(log.text)\n"
        }
        return result
    }
    
    func shareText(_ text: String) {
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true)
        }
    }
}

// MARK: - Ввод суммы
struct AmountInputSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DebtStore
    let targetDebt: DebtItem
    let isDecrease: Bool
    var onComplete: () -> Void
    
    @State private var amountString = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text(isDecrease ? "Списать с долга" : "Добавить к долгу")
                    .font(.headline)
                    .padding(.top, 20)
                
                TextField("0", text: $amountString)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding()
                
                Button(action: {
                    if let val = Double(amountString), val > 0 {
                        store.applyOperation(to: targetDebt, amount: val, isDecrease: isDecrease)
                        onComplete()
                        dismiss()
                    }
                }) {
                    Text("Подтвердить")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Фильтр по дате
struct DatePickerFilterSheet: View {
    @Environment(\.dismiss) var dismiss
    var onApply: (Date, Date) -> Void
    
    @State private var start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var end = Date()
    
    var body: some View {
        NavigationView {
            Form {
                DatePicker("С даты", selection: $start, displayedComponents: .date)
                DatePicker("По дату", selection: $end, displayedComponents: .date)
                
                Button("Сформировать выписку") {
                    onApply(start, end)
                    dismiss()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.blue)
            }
            .navigationTitle("Выбор периода")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Создание контакта (только имя и сумма)
struct AddContactSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DebtStore
    
    @State private var name: String = ""
    @State private var amountString: String = ""
    @State private var selectedType: DebtType = .give
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Picker("Тип", selection: $selectedType) {
                    Text("Мне должен").tag(DebtType.give)
                    Text("Я должен").tag(DebtType.take)
                }
                .pickerStyle(.segmented)
                .padding(.top, 10)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("ИМЯ")
                        .font(.caption.bold())
                        .foregroundColor(.gray)
                    TextField("Например: Рустам", text: $name)
                        .padding()
                        .background(Color.blue.opacity(0.06))
                        .cornerRadius(12)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("СУММА")
                        .font(.caption.bold())
                        .foregroundColor(.gray)
                    TextField("0", text: $amountString)
                        .keyboardType(.numberPad)
                        .padding()
                        .background(Color.blue.opacity(0.06))
                        .cornerRadius(12)
                }
                
                Button(action: {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                          let amount = Double(amountString), amount > 0 else { return }
                    store.addDebt(name: name, amount: amount, type: selectedType)
                    dismiss()
                }) {
                    Text("Сохранить")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(14)
                }
                .padding(.top, 10)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationTitle("Новый контакт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Экран «История» с экспортом всей истории
struct HistoryListView: View {
    @EnvironmentObject var store: DebtStore
    
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Button(action: exportAllHistory) {
                    Label("Скачать всю историю операций", systemImage: "doc.text")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.blue)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                if store.history.isEmpty {
                    Text("История операций пуста")
                        .foregroundColor(.gray)
                        .padding(.top, 40)
                    Spacer()
                } else {
                    List(store.history) { item in
                        HStack {
                            Text(item.text)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                            Spacer()
                            Text(item.date.formatted(date: .numeric, time: .shortened))
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                    .listStyle(.plain)
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("История операций")
        }
    }
    
    func exportAllHistory() {
        var text = "Полный журнал операций Saldo\nВсего записей: \(store.history.count)\n\n"
        for log in store.history {
            text += "\(log.date.formatted(date: .numeric, time: .shortened)) — \(log.text)\n"
        }
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true)
        }
    }
}

// MARK: - Экран «Архив / VIP»
struct ArchiveListView: View {
    @EnvironmentObject var store: DebtStore
    @State private var selectedDebt: DebtItem? = nil
    
    var archivedDebts: [DebtItem] {
        store.debts.filter { $0.isArchived }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if archivedDebts.isEmpty {
                    Text("В архиве пока нет контактов")
                        .foregroundColor(.gray)
                        .padding(.top, 40)
                    Spacer()
                } else {
                    List(archivedDebts) { debt in
                        HStack {
                            Text(debt.name)
                                .font(.headline)
                            Spacer()
                            Text("\(Int(debt.amount)) \(store.currency)")
                                .font(.subheadline.bold())
                            Button("Вернуть") {
                                store.toggleArchive(for: debt)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                    .listStyle(.plain)
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("Архив / VIP")
        }
    }
}

// MARK: - Экран «Настройки»
struct SettingsListView: View {
    @EnvironmentObject var store: DebtStore
    @State private var showConfirmClear = false
    
    let currencies = ["TJS", "USD", "RUB", "EUR", "UZS"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Валюта приложения")) {
                    Picker("Основная валюта", selection: $store.currency) {
                        ForEach(currencies, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                }
                
                Section(header: Text("Управление данными")) {
                    Button(role: .destructive, action: { showConfirmClear = true }) {
                        Text("Стереть все контакты")
                    }
                }
            }
            .navigationTitle("Настройки")
            .confirmationDialog("Вы уверены?", isPresented: $showConfirmClear, titleVisibility: .visible) {
                Button("Стереть всё", role: .destructive) {
                    store.clearAll()
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }
}

// MARK: - Компоненты
struct SummaryCard: View {
    let title: String
    let amount: Double
    let currency: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.gray)
            Text("\(Int(amount)) \(currency)")
                .font(.system(size: 21, weight: .heavy))
                .foregroundColor(.black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue, lineWidth: 2))
    }
}

