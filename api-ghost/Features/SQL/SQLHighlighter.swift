//
//  SQLHighlighter.swift
//  APIGhost
//
//  SQL syntax highlighter that tokenizes and colorizes SQL query text.
//

import SwiftUI

// MARK: - SQL Highlighter

enum SQLHighlighter {
    // MARK: - Keywords

    private static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN",
        "IS", "NULL", "AS", "ON", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER",
        "FULL", "CROSS", "NATURAL", "ORDER", "BY", "ASC", "DESC", "GROUP",
        "HAVING", "LIMIT", "OFFSET", "DISTINCT", "ALL", "UNION", "INTERSECT",
        "EXCEPT", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "TRIGGER",
        "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "UNIQUE", "CHECK",
        "DEFAULT", "CONSTRAINT", "CASCADE", "RESTRICT", "COUNT", "SUM",
        "AVG", "MIN", "MAX", "CASE", "WHEN", "THEN", "ELSE", "END", "CAST",
        "COALESCE", "NULLIF", "EXISTS", "TRUE", "FALSE"
    ]

    // MARK: - Main Entry Point

    static func highlight(_ sql: String) -> AttributedString {
        var result = AttributedString()
        var index = sql.startIndex
        let end = sql.endIndex

        while index < end {
            let char = sql[index]

            if let advanced = tryHighlightStringLiteral(sql: sql, at: index, end: end, result: &result) {
                index = advanced
            } else if let advanced = tryHighlightComment(sql: sql, at: index, end: end, result: &result) {
                index = advanced
            } else if let advanced = tryHighlightNumber(sql: sql, char: char, at: index, end: end, result: &result) {
                index = advanced
            } else if let advanced = tryHighlightWord(sql: sql, char: char, at: index, end: end, result: &result) {
                index = advanced
            } else {
                appendSingleChar(char, to: &result)
                index = sql.index(after: index)
            }
        }

        return result
    }

    // MARK: - Token Handlers

    private static func tryHighlightStringLiteral(
        sql: String,
        at index: String.Index,
        end: String.Index,
        result: inout AttributedString
    ) -> String.Index? {
        let char = sql[index]
        guard char == "'" || char == "\"" else { return nil }

        guard let stringEnd = findStringEnd(in: sql, from: index, delimiter: char) else { return nil }

        let stringContent = String(sql[index...stringEnd])
        var attrString = AttributedString(stringContent)
        attrString.foregroundColor = Color.ghostJsonString
        result.append(attrString)
        return sql.index(after: stringEnd)
    }

    private static func tryHighlightComment(
        sql: String,
        at index: String.Index,
        end: String.Index,
        result: inout AttributedString
    ) -> String.Index? {
        let char = sql[index]
        let nextIndex = sql.index(after: index)
        guard char == "-", nextIndex < end, sql[nextIndex] == "-" else { return nil }

        var commentEnd = sql.index(after: nextIndex)
        while commentEnd < end && sql[commentEnd] != "\n" {
            commentEnd = sql.index(after: commentEnd)
        }
        let commentContent = String(sql[index..<commentEnd])
        var attrString = AttributedString(commentContent)
        attrString.foregroundColor = Color.ghostTextMuted
        result.append(attrString)
        return commentEnd
    }

    private static func tryHighlightNumber(
        sql: String,
        char: Character,
        at index: String.Index,
        end: String.Index,
        result: inout AttributedString
    ) -> String.Index? {
        guard char.isNumber || char == "-" else { return nil }

        let numberStart = index
        var numberEnd = index

        if char == "-" {
            let nextIndex = sql.index(after: index)
            guard nextIndex < end, sql[nextIndex].isNumber else { return nil }
            numberEnd = nextIndex
        }

        while numberEnd < end && (sql[numberEnd].isNumber || sql[numberEnd] == ".") {
            numberEnd = sql.index(after: numberEnd)
        }

        guard numberEnd > numberStart else { return nil }

        let numberStr = String(sql[numberStart..<numberEnd])
        var attrString = AttributedString(numberStr)
        attrString.foregroundColor = Color.ghostJsonNumber
        result.append(attrString)
        return numberEnd
    }

    private static func tryHighlightWord(
        sql: String,
        char: Character,
        at index: String.Index,
        end: String.Index,
        result: inout AttributedString
    ) -> String.Index? {
        guard char.isLetter || char == "_" else { return nil }

        var wordEnd = index
        while wordEnd < end && (sql[wordEnd].isLetter || sql[wordEnd].isNumber || sql[wordEnd] == "_") {
            wordEnd = sql.index(after: wordEnd)
        }

        let word = String(sql[index..<wordEnd])
        var attrString = AttributedString(word)

        attrString.foregroundColor = keywords.contains(word.uppercased())
            ? Color.ghostAccent
            : Color.ghostTextPrimary

        result.append(attrString)
        return wordEnd
    }

    private static func appendSingleChar(_ char: Character, to result: inout AttributedString) {
        var attrString = AttributedString(String(char))
        attrString.foregroundColor = "(),;*=<>!+-/%".contains(char)
            ? Color.ghostTextSecondary
            : Color.ghostTextPrimary
        result.append(attrString)
    }

    // MARK: - String Delimiter Finding

    private static func findStringEnd(
        in sql: String,
        from start: String.Index,
        delimiter: Character
    ) -> String.Index? {
        guard sql[start] == delimiter else { return nil }

        var index = sql.index(after: start)
        while index < sql.endIndex {
            let char = sql[index]
            if char == "\\" && sql.index(after: index) < sql.endIndex {
                index = sql.index(index, offsetBy: 2)
            } else if char == delimiter {
                return index
            } else {
                index = sql.index(after: index)
            }
        }
        return nil
    }
}
