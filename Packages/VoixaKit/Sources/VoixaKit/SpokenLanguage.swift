/// Languages Voixa is tuned for. Raw values are Whisper language codes.
public enum SpokenLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case hindi = "hi"
    case bengali = "bn"
    case urdu = "ur"
    case tamil = "ta"
    case telugu = "te"
    case marathi = "mr"
    case gujarati = "gu"
    case punjabi = "pa"
    case kannada = "kn"
    case malayalam = "ml"
    case nepali = "ne"
    case sinhala = "si"

    public var displayName: String {
        switch self {
        case .english: "English"
        case .hindi: "Hindi"
        case .bengali: "Bengali"
        case .urdu: "Urdu"
        case .tamil: "Tamil"
        case .telugu: "Telugu"
        case .marathi: "Marathi"
        case .gujarati: "Gujarati"
        case .punjabi: "Punjabi"
        case .kannada: "Kannada"
        case .malayalam: "Malayalam"
        case .nepali: "Nepali"
        case .sinhala: "Sinhala"
        }
    }
}
