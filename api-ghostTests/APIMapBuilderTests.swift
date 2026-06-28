import Foundation
import Testing

@testable import APIGhost

@MainActor
@Suite
struct APIMapBuilderTests {
    private func graphqlRow(name: String, type: String, status: Int?, hits: Int) -> RawRow {
        RawRow(
            host: "api.example.com",
            path: "/graphql",
            method: "POST",
            statusCode: status,
            graphqlName: name,
            graphqlType: type,
            hitCount: hits
        )
    }

    // MARK: - Merge

    @Test
    func mergesParameterizedPathsIntoOneEndpoint() throws {
        let rows = [
            RawRow(host: "api.example.com", path: "/users/12847", method: "GET", statusCode: 200),
            RawRow(host: "api.example.com", path: "/users/12848", method: "GET", statusCode: 200, hitCount: 3)
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        let endpoint = try #require(
            MapTestSupport.endpoint(in: domain, method: "GET", normalizedPath: "/users/{id}")
        )
        #expect(domain.uniqueEndpoints == 1)
        #expect(endpoint.hitCount == 4)
        #expect(Set(endpoint.examplePaths) == ["/users/12847", "/users/12848"])
    }

    @Test
    func differentMethodsSamePathStaySeparate() throws {
        let rows = [
            RawRow(host: "api.example.com", path: "/users/1", method: "GET"),
            RawRow(host: "api.example.com", path: "/users/1", method: "POST")
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        #expect(domain.uniqueEndpoints == 2)
        #expect(domain.methods == ["GET", "POST"])
    }

    @Test
    func examplePathsCapAtThree() throws {
        let rows = (0..<5).map {
            RawRow(host: "api.example.com", path: "/users/1234\($0)", method: "GET")
        }
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        let endpoint = try #require(
            MapTestSupport.endpoint(in: domain, method: "GET", normalizedPath: "/users/{id}")
        )
        #expect(endpoint.examplePaths.count == 3)
        #expect(endpoint.hitCount == 5)
    }

    // MARK: - Status rollups

    @Test
    func aggregatesStatusCountsAcrossRows() throws {
        let rows = [
            RawRow(host: "api.example.com", path: "/orders/100", method: "GET", statusCode: 200, hitCount: 5),
            RawRow(host: "api.example.com", path: "/orders/101", method: "GET", statusCode: 404, hitCount: 2),
            RawRow(host: "api.example.com", path: "/orders/102", method: "GET", statusCode: 200, hitCount: 1)
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        let endpoint = try #require(
            MapTestSupport.endpoint(in: domain, method: "GET", normalizedPath: "/orders/{id}")
        )
        #expect(endpoint.statusCounts == [200: 6, 404: 2])
        #expect(endpoint.statusCodes == [200, 404])
        #expect(endpoint.sortedStatusCounts.map(\.code) == [200, 404])
        #expect(endpoint.hitCount == 8)
    }

    @Test
    func nilStatusCodeCountsHitsButNotStatus() throws {
        let rows = [
            RawRow(host: "api.example.com", path: "/ping", method: "GET", statusCode: nil, hitCount: 4)
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        let endpoint = try #require(
            MapTestSupport.endpoint(in: domain, method: "GET", normalizedPath: "/ping")
        )
        #expect(endpoint.hitCount == 4)
        #expect(endpoint.statusCounts.isEmpty)
        #expect(endpoint.successRate == nil)
    }

    @Test
    func successRateIsTwoXXOverTotal() throws {
        let endpoint = APIEndpoint(
            normalizedPath: "/x",
            method: "GET",
            statusCounts: [200: 3, 201: 1, 500: 4]
        )
        let rate = try #require(endpoint.successRate)
        #expect(abs(rate - 0.5) < 0.0001)
    }

    // MARK: - Classification

    @Test
    func targetIsRegistrableDomainWithMostRequests() throws {
        let rows = [
            RawRow(host: "api.target.com", path: "/users/1", method: "GET", hitCount: 100),
            RawRow(host: "cdn.jsdelivr.net", path: "/lib.js", method: "GET", hitCount: 5)
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let target = try #require(MapTestSupport.domain(domains, host: "api.target.com"))
        let thirdParty = try #require(MapTestSupport.domain(domains, host: "cdn.jsdelivr.net"))
        #expect(target.classification == .target)
        #expect(thirdParty.classification == .thirdParty)
        #expect(thirdParty.category == "CDN")
        #expect(target.category == nil)
    }

    @Test
    func subdomainsOfTargetShareTargetClassification() {
        let rows = [
            RawRow(host: "api.target.com", path: "/a/1", method: "GET", hitCount: 50),
            RawRow(host: "auth.target.com", path: "/b/2", method: "GET", hitCount: 50),
            RawRow(host: "other.com", path: "/c/3", method: "GET", hitCount: 10)
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        #expect(MapTestSupport.domain(domains, host: "api.target.com")?.classification == .target)
        #expect(MapTestSupport.domain(domains, host: "auth.target.com")?.classification == .target)
        #expect(MapTestSupport.domain(domains, host: "other.com")?.classification == .thirdParty)
    }

    @Test
    func targetSortsFirstThenThirdPartiesByRequestsDescending() {
        let rows = [
            RawRow(host: "api.target.com", path: "/a/1", method: "GET", hitCount: 100),
            RawRow(host: "small.com", path: "/b/2", method: "GET", hitCount: 5),
            RawRow(host: "big.com", path: "/c/3", method: "GET", hitCount: 40)
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        #expect(domains.map(\.host) == ["api.target.com", "big.com", "small.com"])
    }

    @Test
    func classificationTieBreaksOnEndpointCountThenLexicographic() {
        let rows = [
            RawRow(host: "alpha.com", path: "/a/1", method: "GET", hitCount: 10),
            RawRow(host: "beta.com", path: "/b/1", method: "GET", hitCount: 5),
            RawRow(host: "beta.com", path: "/b/2", method: "POST", hitCount: 5)
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        #expect(MapTestSupport.domain(domains, host: "beta.com")?.classification == .target)
        #expect(MapTestSupport.domain(domains, host: "alpha.com")?.classification == .thirdParty)
    }

    // MARK: - GraphQL grouping

    @Test
    func graphqlRowsGroupIntoPerOperationNodes() throws {
        let rows = [
            graphqlRow(name: "GetUser", type: "query", status: 200, hits: 7),
            graphqlRow(name: "GetUser", type: "query", status: 500, hits: 1),
            graphqlRow(name: "CreatePost", type: "mutation", status: 200, hits: 3)
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        let endpoint = try #require(
            MapTestSupport.endpoint(in: domain, method: "POST", normalizedPath: "/graphql")
        )
        #expect(endpoint.isGraphQL)
        #expect(endpoint.graphqlOperations.count == 2)

        let getUser = try #require(endpoint.graphqlOperations.first { $0.name == "GetUser" })
        #expect(getUser.type == .query)
        #expect(getUser.hitCount == 8)
        #expect(getUser.statusCounts == [200: 7, 500: 1])

        let createPost = try #require(endpoint.graphqlOperations.first { $0.name == "CreatePost" })
        #expect(createPost.type == .mutation)
        #expect(createPost.hitCount == 3)

        #expect(endpoint.graphqlOperations.first?.name == "GetUser")
    }

    @Test(arguments: [
        ("query", GraphQLOperationType.query),
        ("MUTATION", GraphQLOperationType.mutation),
        ("subscription", GraphQLOperationType.subscription),
        ("nonsense", GraphQLOperationType.unknown)
    ])
    func graphqlTypeMapsRawValueIncludingUnknown(raw: String, expected: GraphQLOperationType) throws {
        let rows = [graphqlRow(name: "Op", type: raw, status: nil, hits: 1)]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        let endpoint = try #require(
            MapTestSupport.endpoint(in: domain, method: "POST", normalizedPath: "/graphql")
        )
        #expect(endpoint.graphqlOperations.first?.type == expected)
    }

    @Test
    func restRowsAreNotGraphQL() throws {
        let rows = [
            RawRow(host: "api.example.com", path: "/users/100", method: "GET")
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        let endpoint = try #require(
            MapTestSupport.endpoint(in: domain, method: "GET", normalizedPath: "/users/{id}")
        )
        #expect(!endpoint.isGraphQL)
        #expect(endpoint.graphqlOperations.isEmpty)
    }

    @Test
    func emptyGraphqlNameIsTreatedAsRest() throws {
        let rows = [
            RawRow(host: "api.example.com", path: "/graphql", method: "POST", graphqlName: "")
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        let endpoint = try #require(
            MapTestSupport.endpoint(in: domain, method: "POST", normalizedPath: "/graphql")
        )
        #expect(endpoint.isGraphQL == false)
    }

    // MARK: - Body & content-type rollup

    @Test
    func bodyFlagsAndContentTypesUnionAcrossRows() throws {
        let rows = [
            RawRow(
                host: "api.example.com",
                path: "/users/100",
                method: "POST",
                hasRequestBody: true,
                hasResponseBody: false,
                contentTypes: ["application/json"]
            ),
            RawRow(
                host: "api.example.com",
                path: "/users/200",
                method: "POST",
                hasRequestBody: false,
                hasResponseBody: true,
                contentTypes: ["text/plain"]
            )
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        let endpoint = try #require(
            MapTestSupport.endpoint(in: domain, method: "POST", normalizedPath: "/users/{id}")
        )
        #expect(endpoint.hasRequestBody)
        #expect(endpoint.hasResponseBody)
        #expect(endpoint.contentTypes == ["application/json", "text/plain"])
    }

    // MARK: - Edge cases

    @Test
    func emptyRowsProduceNoDomains() {
        #expect(APIMapBuilder.buildDomains(from: []).isEmpty)
    }

    @Test
    func rootPathRowProducesDomainWithNoTreeNodes() throws {
        let rows = [RawRow(host: "api.example.com", path: "/", method: "GET")]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        #expect(domain.totalRequests == 1)
        #expect(domain.rootNodes.isEmpty)
    }

    @Test
    func methodCaseIsPreservedNotUppercased() throws {
        let rows = [
            RawRow(host: "api.example.com", path: "/users/1", method: "get"),
            RawRow(host: "api.example.com", path: "/users/2", method: "GET")
        ]
        let domains = APIMapBuilder.buildDomains(from: rows)
        let domain = try #require(MapTestSupport.domain(domains, host: "api.example.com"))
        #expect(domain.methods == ["get", "GET"])
        #expect(domain.uniqueEndpoints == 2)
    }
}
