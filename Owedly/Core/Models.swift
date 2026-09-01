import Foundation

enum CompanyOption: String, CaseIterable, Codable {
    case google = "Google"
    case att = "AT&T"
    case amazon = "Amazon"
    case tiktok = "TikTok"
    case bankOfAmerica = "Bank of America"
    case facebook = "Facebook"

    var imageName: String {
        switch self {
        case .google: return "company_google_group"
        case .att: return "company_att_group"
        case .amazon: return "company_amazon_group"
        case .tiktok: return "company_tiktok_group"
        case .bankOfAmerica: return "company_bofa_group"
        case .facebook: return "company_facebook_group"
        }
    }
}

enum TimePeriodOption: String, CaseIterable, Codable {
    case before2020 = "Before 2020"
    case y2020to2022 = "2020 – 2022"
    case y2023to2024 = "2023 – 2024"
    case y2025toNow = "2025 – Now"
}

enum SettlementCategoryCatalog {
    /// User-facing settlement sections. This intentionally includes the broader taxonomy used
    /// across ClassAction.org's settlement/news content, while keeping the labels concise for iOS.
    /// `Upcoming` is a Discover section rather than a matching category.
    static let all: [String] = [
        "Upcoming",
        "Privacy",
        "Data Breach",
        "Automotive",
        "Banking",
        "Retail",
        "Subscriptions",
        "Telecom",
        "Health",
        "Finance",
        "False Advertising",
        "Technology",
        "Antitrust",
        "AI",
        "Child Labor",
        "Civil Rights",
        "Consumer Protection",
        "Defective Product",
        "Discrimination",
        "Education",
        "Employment",
        "Entertainment",
        "Environmental",
        "Food",
        "Fraud",
        "Beauty",
        "Gaming Addiction",
        "Insurance",
        "Labor Law Violation",
        "Overbilling",
        "Pets",
        "PFAS",
        "Product Recall",
        "Property Rights",
        "Real Estate",
        "Securities",
        "Sexual Abuse",
        "Spam Texts",
        "Sports",
        "Wage and Hour"
    ]

    static let upcoming = "Upcoming"

    static func ordered(_ values: Set<String>) -> [String] {
        let canonical = all.filter(values.contains)
        let extras = values.subtracting(Set(all)).sorted()
        return canonical + extras
    }
}

enum NoticeAnswer: String, CaseIterable, Codable {
    case yes = "Yes"
    case no = "No"
    case notSure = "Not sure"
}

enum ProofAnswer: String, CaseIterable, Codable {
    case yes = "Yes"
    case sometimes = "Sometimes"
    case no = "No"
}

struct OnboardingDraft: Codable {
    var selectedStates: Set<String> = []
    var selectedCompanies: Set<CompanyOption> = []
    var selectedTimePeriods: Set<TimePeriodOption> = []
    var selectedCategories: Set<String> = []
    var noticeAnswer: NoticeAnswer?
    var proofAnswer: ProofAnswer?
    var onboardingCompleted = false
}

final class OnboardingStore {
    static let shared = OnboardingStore()

    private let defaults: UserDefaults
    private let key = "owedly.onboarding.draft.v1"
    private let persistsChanges: Bool

    private(set) var draft: OnboardingDraft {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.persistsChanges = true
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(OnboardingDraft.self, from: data) {
            self.draft = decoded
        } else {
            self.draft = OnboardingDraft()
        }
    }

    /// A non-persisting copy used by Settings editors. Changes stay isolated until the user
    /// explicitly taps Save, so cancelling an edit never mutates the real onboarding profile.
    init(initialDraft: OnboardingDraft) {
        self.defaults = .standard
        self.persistsChanges = false
        self.draft = initialDraft
    }

    func update(_ mutation: (inout OnboardingDraft) -> Void) {
        mutation(&draft)
    }

    func markCompleted() {
        update { $0.onboardingCompleted = true }
    }

    func resetForTesting() {
        draft = OnboardingDraft()
    }

    /// Clears locally stored matching/profile answers while keeping onboarding completed so the
    /// user stays in the main app. Purchase state and non-personal app preferences are untouched.
    func clearPersonalInformation() {
        let completed = draft.onboardingCompleted
        draft = OnboardingDraft(onboardingCompleted: completed)
    }

    private func persist() {
        guard persistsChanges, let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key)
    }
}
