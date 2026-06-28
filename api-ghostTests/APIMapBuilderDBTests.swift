import Foundation
import Testing

@testable import APIGhost

@MainActor
struct APIMapBuilderDBTests {
    private let db: IsolatedCaptureDatabase

    init() throws {
        db = try IsolatedCaptureDatabase()
    }

    private func cap(
        _ method: String,
        _ host: String,
        _ path: String,
        status: Int? = nil,
        ct: String? = nil,
        respSize: Int = 0,
        gql: String? = nil,
        gqlType: String? = nil
    ) -> Capture {
        Capture(
            method: method,
            scheme: "https",
            host: host,
            path: path,
            statusCode: status,
            responseBodySize: respSize,
            contentType: ct,
            graphqlOperationName: gql,
            graphqlOperationType: gqlType
        )
    }

    @Test
    func buildMapMergesUppercasesAndAggregatesFromDatabase() async throws {
        try db.reseed(with: [
            cap("get", "api.example.com", "/v1/users/12847", status: 200, ct: "application/json", respSize: 10),
            cap("GET", "api.example.com", "/v1/users/12848", status: 200, ct: "application/xml", respSize: 20),
            cap("POST", "cdn.jsdelivr.net", "/npm/lib", status: 200)
        ])

        let domains = try await db.mapBuilder.buildMap()

        let target = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        #expect(target.classification == .target)

        let endpoint = try #require(
            MapTestSupport.endpoint(in: target, method: "GET", normalizedPath: "/v1/users/{id}")
        )
        #expect(endpoint.method == "GET")
        #expect(endpoint.hitCount == 2)
        #expect(endpoint.hasResponseBody)
        #expect(endpoint.contentTypes == ["application/json", "application/xml"])

        let thirdParty = try #require(MapTestSupport.domain(domains, host: "cdn.jsdelivr.net"))
        #expect(thirdParty.classification == .thirdParty)
        #expect(thirdParty.category == "CDN")
    }

    @Test
    func buildMapGroupsGraphQLOperationsFromDatabase() async throws {
        try db.reseed(with: [
            cap("POST", "api.example.com", "/graphql", status: 200, gql: "GetUser", gqlType: "query"),
            cap("POST", "api.example.com", "/graphql", status: 200, gql: "GetUser", gqlType: "query")
        ])

        let domains = try await db.mapBuilder.buildMap()
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        let endpoint = try #require(
            MapTestSupport.endpoint(in: domain, method: "POST", normalizedPath: "/graphql")
        )
        #expect(endpoint.isGraphQL)
        let operation = try #require(endpoint.graphqlOperations.first)
        #expect(operation.name == "GetUser")
        #expect(operation.type == .query)
        #expect(operation.hitCount == 2)
    }

    @Test
    func buildStatisticsReportsCountsFromDatabase() async throws {
        try db.reseed(with: [
            cap("GET", "api.example.com", "/a", status: 200),
            cap("POST", "api.example.com", "/b", status: 201),
            cap("GET", "cdn.jsdelivr.net", "/c", status: nil)
        ])

        let stats = try await db.mapBuilder.buildStatistics()
        #expect(stats.totalRequests == 3)
        #expect(stats.domainCount == 2)
        #expect(stats.endpointCount == 3)
        #expect(stats.methodBreakdown["GET"] == 2)
        #expect(stats.methodBreakdown["POST"] == 1)
        #expect(stats.statusCodeBreakdown[200] == 1)
        #expect(stats.statusCodeBreakdown[201] == 1)
        #expect(stats.statusCodeBreakdown.values.reduce(0, +) == 2)
    }
}
