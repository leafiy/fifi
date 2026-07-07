import Foundation

public enum FuzzyScorer {
    private static let queryWhitespace = CharacterSet.whitespacesAndNewlines
    private static let boundaryWhitespace = CharacterSet.whitespacesAndNewlines
    private static let boundaryPunctuation = CharacterSet.punctuationCharacters
    private static let lowercaseLetters = CharacterSet.lowercaseLetters
    private static let uppercaseLetters = CharacterSet.uppercaseLetters

    /// Returns nil when `query` is not a case-insensitive subsequence of `candidate`.
    /// Whitespace in `query` is ignored, so tokens are matched as one ordered subsequence.
    /// Higher scores are better. Empty query returns nil.
    public static func score(query: String, candidate: String) -> Double? {
        var strippedQuery = ""
        strippedQuery.reserveCapacity(query.count)
        for character in query where !isQueryWhitespace(character) {
            strippedQuery.append(character)
        }

        guard !strippedQuery.isEmpty else { return nil }

        let candidateCharacters = Array(candidate)
        guard strippedQuery.count <= candidateCharacters.count else { return nil }

        let queryCharacters = Array(strippedQuery.lowercased())
        var foldedCandidateCharacters: [Character] = []
        var foldedCandidateIndexes: [Int] = []
        foldedCandidateCharacters.reserveCapacity(candidateCharacters.count)
        foldedCandidateIndexes.reserveCapacity(candidateCharacters.count)
        for (candidateIndex, character) in candidateCharacters.enumerated() {
            for foldedCharacter in String(character).lowercased() {
                foldedCandidateCharacters.append(foldedCharacter)
                foldedCandidateIndexes.append(candidateIndex)
            }
        }

        guard queryCharacters.count <= foldedCandidateCharacters.count else { return nil }

        var queryIndex = 0
        var previousMatchFoldedIndex: Int?
        var consecutiveRunLength = 0
        var totalScore = 0.0

        for foldedIndex in foldedCandidateCharacters.indices {
            guard foldedCandidateCharacters[foldedIndex] == queryCharacters[queryIndex] else {
                continue
            }

            let candidateIndex = foldedCandidateIndexes[foldedIndex]
            totalScore += 10.0

            if candidateIndex == 0 {
                totalScore += 20.0
            } else if isWordBoundary(previous: candidateCharacters[candidateIndex - 1], current: candidateCharacters[candidateIndex]) {
                totalScore += 15.0
            }

            if let previousMatchFoldedIndex {
                let gap = foldedIndex - previousMatchFoldedIndex - 1
                if gap == 0 {
                    consecutiveRunLength += 1
                    totalScore += 8.0 + Double(consecutiveRunLength)
                } else {
                    consecutiveRunLength = 0
                    totalScore -= Double(gap) * 0.75
                }
            } else {
                totalScore -= Double(foldedIndex) * 0.75
            }

            previousMatchFoldedIndex = foldedIndex
            queryIndex += 1
            if queryIndex == queryCharacters.count {
                return totalScore - (Double(candidateCharacters.count) * 0.01)
            }
        }

        return nil
    }

    private static func isQueryWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { queryWhitespace.contains($0) }
    }

    private static func isWordBoundary(previous: Character, current: Character) -> Bool {
        isBoundarySeparator(previous) || (containsLowercaseLetter(previous) && containsUppercaseLetter(current))
    }

    private static func isBoundarySeparator(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            boundaryWhitespace.contains(scalar)
                || boundaryPunctuation.contains(scalar)
                || scalar.value == 95
                || scalar.value == 45
                || scalar.value == 47
        }
    }

    private static func containsLowercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { lowercaseLetters.contains($0) }
    }

    private static func containsUppercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { uppercaseLetters.contains($0) }
    }
}
