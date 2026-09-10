extension String {
    /// The two-letter monogram the mockup shows in place of a logo: the first letters of
    /// the first two words, skipping "the", "of" and "and" and anything not starting with
    /// a letter. "Great Western Power Company" → "GW", "The Peak of Fremont" → "PF".
    var initials: String {
        let skipped: Set<String> = ["the", "of", "and"]
        return split(separator: " ")
            .filter { word in
                guard let first = word.first, first.isLetter else { return false }
                return !skipped.contains(word.lowercased())
            }
            .prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
    }
}
