import Foundation
import Testing

@testable import APIGhost

@Suite
struct EndpointDetailTests {
    @Test
    func fromEndpointCarriesRollupFields() {
        let endpoint = APIEndpoint(
            normalizedPath: "/users/{id}",
            method: "GET",
            statusCounts: [200: 4, 500: 1],
            hitCount: 5,
            examplePaths: ["/users/1", "/users/2"],
            contentTypes: ["text/plain", "application/json"]
        )
        let detail = EndpointDetail.from(endpoint: endpoint, host: "api.example.com")

        #expect(detail.id == endpoint.id)
        #expect(detail.method == "GET")
        #expect(detail.graphqlType == nil)
        #expect(detail.title == "/users/{id}")
        #expect(detail.host == "api.example.com")
        #expect(detail.summary == "Parameterized from 5 captures")
        #expect(detail.hitCount == 5)
        #expect(detail.statusCounts == [200: 4, 500: 1])
        #expect(detail.examplePaths == ["/users/1", "/users/2"])
        #expect(detail.contentTypes == ["application/json", "text/plain"])
    }

    @Test
    func fromOperationCarriesGraphQLFields() {
        let operation = GraphQLOperation(
            name: "GetUser",
            type: .query,
            hitCount: 9,
            statusCounts: [200: 9]
        )
        let detail = EndpointDetail.from(operation: operation, host: "api.example.com")

        #expect(detail.id == operation.id)
        #expect(detail.method == "query")
        #expect(detail.graphqlType == .query)
        #expect(detail.title == "GetUser")
        #expect(detail.host == "api.example.com")
        #expect(detail.summary == "query · 9 captures")
        #expect(detail.hitCount == 9)
        #expect(detail.statusCounts == [200: 9])
        #expect(detail.examplePaths.isEmpty)
        #expect(detail.contentTypes.isEmpty)
    }

    @Test
    func sortedStatusCountsAscendingAndSuccessRate() throws {
        let operation = GraphQLOperation(
            name: "Op",
            type: .mutation,
            hitCount: 10,
            statusCounts: [500: 2, 200: 6, 404: 2]
        )
        let detail = EndpointDetail.from(operation: operation, host: "h")

        #expect(detail.sortedStatusCounts.map(\.code) == [200, 404, 500])
        let rate = try #require(detail.successRate)
        #expect(abs(rate - 0.6) < 0.0001)
    }
}
