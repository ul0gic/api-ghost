import Foundation
import Testing

@testable import APIGhost

@Suite
struct GraphQLParserTests {
    private static let endpoint = "https://api.example.com/graphql"

    private func requireURL(_ string: String) throws -> URL {
        try #require(URL(string: string), "test URL must be valid: \(string)")
    }

    private func parse(post object: Any, contentType: String? = "application/json") throws -> GraphQLOperationInfo? {
        let url = try requireURL(Self.endpoint)
        let body = try JSONSerialization.data(withJSONObject: object)
        return GraphQLParser.parse(method: "POST", url: url, contentType: contentType, body: body)
    }

    // MARK: - Common POST shapes

    @Test(arguments: [
        ("query GetUser { user { id name } }", "GetUser", GraphQLOperationType.query),
        ("mutation CreatePost { createPost { id } }", "CreatePost", GraphQLOperationType.mutation),
        ("subscription OnMessageAdded { messageAdded { id } }", "OnMessageAdded", GraphQLOperationType.subscription)
    ])
    func namedOperationParsesTypeAndName(
        query: String,
        operationName: String,
        expectedType: GraphQLOperationType
    ) throws {
        let info = try #require(try parse(post: [
            "query": query,
            "operationName": operationName,
            "variables": ["id": "1"]
        ]))
        #expect(info.operationType == expectedType)
        #expect(info.operationName == operationName)
        #expect(info.isPersisted == false)
        #expect(info.isBatch == false)
    }

    @Test
    func queryTypeDerivedFromKeywordWithoutOperationNameField() throws {
        let info = try #require(try parse(post: ["query": "query { viewer { id } }"]))
        #expect(info.operationType == .query)
        #expect(info.isPersisted == false)
        #expect(info.isBatch == false)
    }

    @Test
    func leadingWhitespaceBeforeKeywordStillResolvesType() throws {
        let info = try #require(try parse(post: [
            "query": "\n\n   mutation CreatePost { createPost { id } }\n",
            "operationName": "CreatePost"
        ]))
        #expect(info.operationType == .mutation, "keyword detection must tolerate leading whitespace/newlines")
        #expect(info.operationName == "CreatePost")
    }

    // MARK: - Graceful degradation

    @Test
    func batchedArrayBodyIsLabeledFromFirstOperation() throws {
        let info = try #require(try parse(post: [
            ["query": "query A { a }", "operationName": "A"],
            ["query": "mutation B { b }", "operationName": "B"]
        ]))
        #expect(info.isBatch == true, "a batched GraphQL array must be labeled, never choke")
        #expect(info.operationType == .query, "batch summary takes the first operation's type")
        #expect(info.operationName == "A")
    }

    @Test
    func persistedQueryWithoutQueryTextIsFlaggedPersisted() throws {
        let info = try #require(try parse(post: [
            "operationName": "GetUser",
            "variables": ["id": "1"],
            "extensions": ["persistedQuery": ["version": 1, "sha256Hash": "deadbeef"]]
        ]))
        #expect(info.isPersisted == true)
        #expect(info.operationName == "GetUser")
        #expect(info.operationType == .unknown, "no query text means the type cannot be derived")
    }

    @Test
    func getBasedGraphQLParsesFromQueryParameters() throws {
        let url = try requireURL(
            "https://api.example.com/graphql?query=query%20GetUser%20%7B%20user%20%7B%20id%20%7D%20%7D&operationName=GetUser"
        )
        let info = try #require(GraphQLParser.parse(method: "GET", url: url, contentType: nil, body: nil))
        #expect(info.operationType == .query)
        #expect(info.operationName == "GetUser")
    }

    // MARK: - Error & edge paths

    @Test
    func malformedBodyReturnsNilOrUnknownNeverThrows() throws {
        let url = try requireURL(Self.endpoint)
        let info = GraphQLParser.parse(
            method: "POST",
            url: url,
            contentType: "application/json",
            body: Data("{ this is not valid json".utf8)
        )
        #expect(info == nil || info?.operationType == .unknown)
    }

    @Test
    func emptyBodyReturnsNilOrUnknownNeverThrows() throws {
        let url = try requireURL(Self.endpoint)
        let info = GraphQLParser.parse(method: "POST", url: url, contentType: "application/json", body: Data())
        #expect(info == nil || info?.operationType == .unknown)
    }

    @Test
    func restRequestWithNoGraphQLMarkersReturnsNil() throws {
        let url = try requireURL("https://api.example.com/v1/users")
        let body = try JSONSerialization.data(withJSONObject: ["name": "Ada", "email": "ada@example.com"])
        let info = GraphQLParser.parse(method: "POST", url: url, contentType: "application/json", body: body)
        #expect(info == nil, "a REST body with no GraphQL markers must not be classified as GraphQL")
    }

    @Test
    func plainGetWithNoGraphQLMarkersReturnsNil() throws {
        let url = try requireURL("https://api.example.com/v1/users")
        let info = GraphQLParser.parse(method: "GET", url: url, contentType: nil, body: nil)
        #expect(info == nil)
    }

    @Test
    func restBodyWithQueryFieldOnNonGraphQLPathIsNotClassifiedAsGraphQL() throws {
        let url = try requireURL("https://api.example.com/v1/search")
        let body = try JSONSerialization.data(withJSONObject: ["query": "subscription plans and pricing"])
        let info = GraphQLParser.parse(method: "POST", url: url, contentType: "application/json", body: body)
        #expect(info == nil, "a REST search body with a 'query' string must not be treated as GraphQL")
    }

    @Test
    func bodyOnlyQueryWithSelectionSetOnNonGraphQLPathIsClassified() throws {
        let url = try requireURL("https://api.example.com/v1/data")
        let body = try JSONSerialization.data(withJSONObject: ["query": "query GetUser { user { id } }"])
        let info = try #require(
            GraphQLParser.parse(method: "POST", url: url, contentType: "application/json", body: body),
            "a real GraphQL document in a 'query' field must be classified even off a GraphQL path"
        )
        #expect(info.operationType == .query)
        #expect(info.operationName == "GetUser")
    }

    // MARK: - Column mapping

    @Test
    func storedOperationTypeIsNilForUnknownAndRawValueOtherwise() {
        #expect(GraphQLOperationInfo(operationName: nil, operationType: .unknown).storedOperationType == nil,
                ".unknown writes NULL so it never pollutes API Map grouping")
        #expect(GraphQLOperationInfo(operationName: "X", operationType: .query).storedOperationType == "query")
        #expect(GraphQLOperationInfo(operationName: "X", operationType: .mutation).storedOperationType == "mutation")
    }
}
