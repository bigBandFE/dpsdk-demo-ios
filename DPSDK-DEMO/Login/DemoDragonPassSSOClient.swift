import CommonCrypto
import Foundation
import Security

final class DemoDragonPassSSOClient {
    static let shared = DemoDragonPassSSOClient()

    private enum Constants {
        static let openAPIOperationCode = "get_login_free_redirect_url"
        static let openAPIVersion = "1.0"
        static let requestTimeout: TimeInterval = 60
        static let openAPIContentType = "application/json"
        static let visitorLoginAccept = "application/json, text/plain, */*"
        static let visitorLoginGlobal = "true"
    }

    private let config: DemoDragonPassSSOConfig
    private let session: URLSession

    init(config: DemoDragonPassSSOConfig = .bundleDefault(), session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Public API

    func getAuthCode(requestId: String = "req-\(Int(Date().timeIntervalSince1970 * 1000))") async throws -> String {
        try validateConfig()

        let body = config.openapiBody()
        logSSOStart(requestId: requestId, body: body)

        let encryptedRequest = try buildEncryptedRequest(
            operationCode: Constants.openAPIOperationCode,
            plainBody: body,
            requestId: requestId
        )
        logEncryptedOpenAPIRequest(encryptedRequest)

        let openAPIResponse = try await sendOpenAPIRequest(encryptedRequest)
        logOpenAPIResponse(openAPIResponse)

        let decryptedBody = try decryptOpenAPIResponse(openAPIResponse)
        let shortCode = try resolveShortCode(from: decryptedBody)

        let visitorResponse = try await sendVisitorLogin(shortCode: shortCode)
        let token = try extractVisitorToken(from: visitorResponse)
        logAuthCodeSuccess(token)
        return token
    }

    func getAndStoreAuthCode() async throws -> String {
        log("store_auth_code.start")
        let token = try await getAuthCode()
        DemoLoginSessionStore.shared.storeBridgeSession(token: token)
        log("store_auth_code.done", [
            "authCodeLength": token.count,
            "authCodePreview": mask(token)
        ])
        return token
    }

    // MARK: - Validation

    private func validateConfig() throws {
        let missingKeys = [
            config.saasPublicKey.isEmpty ? "DPSaasPublicKey" : nil,
            config.customerPrivateKey.isEmpty ? "DPCustomerPrivateKey" : nil
        ].compactMap { $0 }

        if !missingKeys.isEmpty {
            log("config.invalid", [
                "missingKeys": missingKeys,
                "message": "SSO RSA keys are required before App-side SSO can run"
            ])
            throw DemoLoginAPIError.server(
                code: "SSO_CONFIG_MISSING_RSA_KEY",
                message: "Missing SSO config: \(missingKeys.joined(separator: ", "))"
            )
        }

        let invalidKeys = [
            !config.saasPublicKey.contains("BEGIN PUBLIC KEY") ? "DPSaasPublicKey" : nil,
            (!config.customerPrivateKey.contains("BEGIN") || !config.customerPrivateKey.contains("PRIVATE KEY")) ? "DPCustomerPrivateKey" : nil
        ].compactMap { $0 }

        if !invalidKeys.isEmpty {
            log("config.invalid", [
                "invalidKeys": invalidKeys,
                "message": "RSA keys must be PEM formatted strings"
            ])
            throw DemoLoginAPIError.server(
                code: "SSO_CONFIG_INVALID_RSA_KEY",
                message: "Invalid SSO RSA key format: \(invalidKeys.joined(separator: ", "))"
            )
        }
    }

    // MARK: - OpenAPI

    private func buildEncryptedRequest(operationCode: String, plainBody: OpenAPIRequest.PlainBody, requestId: String) throws -> OpenAPIRequest.EncryptedRequest {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let nonce = "nonce-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let aesKey = try Crypto.randomBytes(count: 16).base64EncodedString()
        let iv = try Crypto.randomBytes(count: 16).base64EncodedString()
        let bodyData = try JSONEncoder().encode(plainBody)
        let bodyText = String(decoding: bodyData, as: UTF8.self)
        let encryptedBody = try Crypto.encryptAES(plainText: bodyText, keyBase64: aesKey, ivBase64: iv)
        let encryptKey = try Crypto.encryptRSA(plainText: aesKey, publicKeyPEM: config.saasPublicKey)
        let signContent = "\(timestamp)\(nonce)\(config.tenantCode)\(encryptKey)\(iv)\(encryptedBody)"
        let sign = try Crypto.signSHA256RSA(signContent, privateKeyPEM: config.customerPrivateKey)

        let headers = [
            "Content-Type": Constants.openAPIContentType,
            "X-Tenant-Code": config.tenantCode,
            "X-Timestamp": String(timestamp),
            "X-Nonce": nonce,
            "X-Sign": sign
        ]

        let body = OpenAPIRequest.EncryptedBody(
            operationCode: operationCode,
            requestId: requestId,
            version: Constants.openAPIVersion,
            encryptKey: encryptKey,
            iv: iv,
            body: encryptedBody
        )

        return OpenAPIRequest.EncryptedRequest(headers: headers, body: body)
    }

    private func sendOpenAPIRequest(_ encryptedRequest: OpenAPIRequest.EncryptedRequest) async throws -> OpenAPIResponse.EncryptedBody {
        guard let url = URL(string: config.openapiBaseURL) else {
            throw DemoLoginAPIError.server(code: "INVALID_OPENAPI_URL", message: "Invalid DragonPass OpenAPI URL")
        }

        log("openapi.request.start", [
            "url": url.absoluteString,
            "method": "POST",
            "tenantCode": config.tenantCode,
            "operationCode": encryptedRequest.body.operationCode,
            "requestId": encryptedRequest.body.requestId
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Constants.requestTimeout
        encryptedRequest.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONEncoder().encode(encryptedRequest.body)

        let (data, urlResponse) = try await session.data(for: request)
        log("openapi.http.response", [
            "httpStatus": (urlResponse as? HTTPURLResponse)?.statusCode ?? -1,
            "responseBytes": data.count,
            "rawPreview": rawPreview(data)
        ])
        return try decodeResponse(data, as: OpenAPIResponse.EncryptedBody.self, context: "OpenAPI")
    }

    private func decryptOpenAPIResponse(_ response: OpenAPIResponse.EncryptedBody) throws -> OpenAPIResponse.DecryptedBody {
        let signContent = "\(response.timestamp)\(response.nonce)\(response.tenantCode)\(response.encryptKey)\(response.iv)\(response.body)"
        log("openapi.verify.start", [
            "signContentLength": signContent.count,
            "signatureLength": response.sign.count
        ])
        let signatureOK = try Crypto.verifySHA256RSA(signContent, signatureBase64: response.sign, publicKeyPEM: config.saasPublicKey)
        log("openapi.verify.done", [
            "signatureOK": String(signatureOK)
        ])
        guard signatureOK else {
            throw DemoLoginAPIError.server(code: "OPENAPI_SIGNATURE_INVALID", message: "DragonPass OpenAPI response signature verification failed")
        }

        let aesKey = try Crypto.decryptRSA(cipherTextBase64: response.encryptKey, privateKeyPEM: config.customerPrivateKey)
        log("openapi.response_key.decrypted", [
            "aesKeyLength": aesKey.count,
            "aesKeyPreview": mask(aesKey)
        ])
        let plainText = try Crypto.decryptAES(cipherTextBase64: response.body, keyBase64: aesKey, ivBase64: response.iv)
        log("openapi.response_body.decrypted", [
            "plainTextLength": plainText.count,
            "plainText": plainText
        ])
        guard let data = plainText.data(using: .utf8) else {
            throw DemoLoginAPIError.decoding("OpenAPI decrypted response is not UTF-8")
        }

        do {
            return try JSONDecoder().decode(OpenAPIResponse.DecryptedBody.self, from: data)
        } catch {
            throw DemoLoginAPIError.decoding("OpenAPI decrypted response parse failed: \(error.localizedDescription), raw: \(plainText)")
        }
    }

    private func resolveShortCode(from response: OpenAPIResponse.DecryptedBody) throws -> String {
        log("openapi.decrypted", [
            "code": response.code ?? "<nil>",
            "msg": response.msg ?? response.message ?? "<nil>",
            "hasShortUrl": String(!(response.data?.shortUrl ?? "").isEmpty),
            "shortUrl": response.data?.shortUrl ?? "<nil>"
        ])

        guard let shortUrl = response.data?.shortUrl, !shortUrl.isEmpty else {
            log("openapi.missing_short_url", [
                "code": response.code ?? "<nil>",
                "msg": response.msg ?? response.message ?? "<nil>"
            ])
            throw DemoLoginAPIError.server(
                code: "NO_SHORT_URL",
                message: "DragonPass OpenAPI response did not include shortUrl"
            )
        }

        let shortCode = try extractShortCode(from: shortUrl)
        log("short_url.extracted", [
            "shortUrl": shortUrl,
            "shortCodePreview": mask(shortCode),
            "shortCodeLength": shortCode.count
        ])
        return shortCode
    }

    // MARK: - Visitor Login

    private func sendVisitorLogin(shortCode: String) async throws -> VisitorLoginResponse.Body {
        let requestData = try makeVisitorLoginRequest(shortCode: shortCode)

        log("visitor_login.request.start", [
            "url": requestData.url.absoluteString,
            "method": "POST",
            "tenantCode": config.tenantCode,
            "productCode": config.loginProductCode,
            "verifyPurchaseProCode": config.verifyPurchaseProCode.isEmpty ? "<empty>" : config.verifyPurchaseProCode,
            "shortCodePreview": mask(shortCode),
            "shortCodeLength": shortCode.count,
            "body": requestData.body.asDictionary
        ])

        var request = URLRequest(url: requestData.url)
        request.httpMethod = "POST"
        request.timeoutInterval = Constants.requestTimeout
        request.setValue(Constants.openAPIContentType, forHTTPHeaderField: "Content-Type")
        request.setValue(Constants.visitorLoginAccept, forHTTPHeaderField: "Accept")
        request.setValue(String(Int(Date().timeIntervalSince1970 * 1000)), forHTTPHeaderField: "timestamp")
        request.setValue(Constants.visitorLoginGlobal, forHTTPHeaderField: "is-global")
        request.setValue(config.language, forHTTPHeaderField: "HTTP-HEADER-LANGUAGE")
        request.setValue(config.language, forHTTPHeaderField: "language")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestData.body.asDictionary)

        let (data, urlResponse) = try await session.data(for: request)
        log("visitor_login.http.response", [
            "httpStatus": (urlResponse as? HTTPURLResponse)?.statusCode ?? -1,
            "responseBytes": data.count,
            "rawPreview": rawPreview(data)
        ])
        return try decodeResponse(data, as: VisitorLoginResponse.Body.self, context: "Visitor login")
    }

    private func makeVisitorLoginRequest(shortCode: String) throws -> VisitorLoginRequest {
        let baseURL = config.visitorLoginBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = config.visitorLoginPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw DemoLoginAPIError.server(code: "INVALID_VISITOR_LOGIN_URL", message: "Invalid visitor login URL")
        }
        return VisitorLoginRequest(
            url: url,
            body: .init(
                params: shortCode,
                tenantCode: config.tenantCode,
                productCode: config.loginProductCode,
                verifyPurchaseProCode: config.verifyPurchaseProCode.isEmpty ? nil : config.verifyPurchaseProCode
            )
        )
    }

    private func extractVisitorToken(from response: VisitorLoginResponse.Body) throws -> String {
        let token = response.data?.token
        log("visitor_login.response.received", [
            "code": response.code ?? "<nil>",
            "msg": response.msg ?? "<nil>",
            "hasToken": String(!(token ?? "").isEmpty),
            "tokenLength": token?.count ?? 0,
            "tokenPreview": mask(token)
        ])

        guard let token, !token.isEmpty else {
            log("visitor_login.missing_auth_code", [
                "code": response.code ?? "<nil>",
                "msg": response.msg ?? "<nil>"
            ])
            throw DemoLoginAPIError.server(
                code: "NO_AUTH_CODE",
                message: "Visitor login response did not include H5 auth code"
            )
        }

        return token
    }

    // MARK: - Shared Helpers

    private func extractShortCode(from shortUrl: String) throws -> String {
        guard let url = URL(string: shortUrl) else {
            throw DemoLoginAPIError.server(code: "INVALID_SHORT_URL", message: "Invalid shortUrl")
        }

        guard let shortCode = url.pathComponents.last, shortCode != "/" else {
            throw DemoLoginAPIError.server(code: "INVALID_SHORT_URL", message: "Cannot extract short code from shortUrl")
        }

        return shortCode
    }

    private func decodeResponse<T: Decodable>(_ data: Data, as type: T.Type, context: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            log("\(context.lowercased().replacingOccurrences(of: " ", with: "_")).decode.error", [
                "error": error.localizedDescription,
                "raw": raw
            ])
            throw DemoLoginAPIError.decoding("\(context) response parse failed: \(error.localizedDescription), raw: \(raw)")
        }
    }

    // MARK: - Logging

    private func logSSOStart(requestId: String, body: OpenAPIRequest.PlainBody) {
        log("getAuthCode.start", [
            "requestId": requestId,
            "tenantCode": config.tenantCode,
            "memberShipCode": mask(config.memberShipCode),
            "openapiBaseURL": config.openapiBaseURL,
            "visitorLoginBaseURL": config.visitorLoginBaseURL,
            "visitorLoginPath": config.visitorLoginPath,
            "loginProductCode": config.loginProductCode,
            "verifyPurchaseProCode": config.verifyPurchaseProCode.isEmpty ? "<empty>" : config.verifyPurchaseProCode,
            "language": config.language,
            "channel": config.channel,
            "module": config.module,
            "redirectURL": config.redirectURL,
            "hasSaasPublicKey": !config.saasPublicKey.isEmpty,
            "saasPublicKeyLength": config.saasPublicKey.count,
            "hasCustomerPrivateKey": !config.customerPrivateKey.isEmpty,
            "customerPrivateKeyLength": config.customerPrivateKey.count
        ])
        log("openapi.body.ready", openAPIBodyLog(body))
    }

    private func logEncryptedOpenAPIRequest(_ request: OpenAPIRequest.EncryptedRequest) {
        log("openapi.encrypted_request.ready", [
            "operationCode": request.body.operationCode,
            "requestId": request.body.requestId,
            "version": request.body.version,
            "encryptKeyLength": request.body.encryptKey.count,
            "ivLength": request.body.iv.count,
            "bodyLength": request.body.body.count,
            "signPreview": mask(request.headers["X-Sign"]),
            "timestamp": request.headers["X-Timestamp"] ?? "",
            "nonce": request.headers["X-Nonce"] ?? ""
        ])
    }

    private func logOpenAPIResponse(_ response: OpenAPIResponse.EncryptedBody) {
        log("openapi.response.received", [
            "tenantCode": response.tenantCode,
            "timestamp": String(response.timestamp),
            "nonce": response.nonce,
            "encryptKeyLength": response.encryptKey.count,
            "ivLength": response.iv.count,
            "bodyLength": response.body.count,
            "signPreview": mask(response.sign)
        ])
    }

    private func logAuthCodeSuccess(_ token: String) {
        log("getAuthCode.success", [
            "authCodeLength": token.count,
            "authCodePreview": mask(token)
        ])
    }

    private func log(_ step: String, _ details: [String: Any] = [:]) {
        print("[DPSDK-DEMO][SSO] \(step) \(details)")
    }

    private func mask(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "<empty>" }
        if value.count <= 8 {
            return "\(value.prefix(2))***"
        }
        return "\(value.prefix(4))...\(value.suffix(4))"
    }

    private func rawPreview(_ data: Data, limit: Int = 600) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "<binary>"
        guard raw.count > limit else { return raw }
        return "\(raw.prefix(limit))...<truncated \(raw.count - limit) chars>"
    }

    private func openAPIBodyLog(_ body: OpenAPIRequest.PlainBody) -> [String: Any] {
        [
            "tenantCode": body.tenantCode,
            "memberShipCode": mask(body.memberShipCode),
            "redirectURL": body.redirectURL,
            "generateShortUrl": body.generateShortUrl,
            "language": body.language,
            "channel": body.channel,
            "productCode": body.productCode,
            "maxPassengerPerOrder": body.maxPassengerPerOrder,
            "pageType": body.pageType,
            "module": body.module,
            "actionType": body.actionType,
            "thirdInfo": body.thirdInfo,
            "timeZone": body.timeZone
        ]
    }
}

enum DemoLoginAPIError: LocalizedError {
    case decoding(String)
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .decoding(let message):
            return "Response parse failed: \(message)"
        case .server(_, let message):
            return message
        }
    }
}

struct DemoDragonPassSSOConfig {
    private enum Defaults {
        static let tenantCode = "0435"
        static let memberShipCode = "8575888265903517"
        static let loginProductCode = "IL0435000001"
        static let verifyPurchaseProCode = "IL0435000002"
        static let language = "en-US"
        static let channel = "eBridge"
        static let module = "1"
        static let redirectURL = "https://g-front-uat.dragonpass.com/standard-lfd/#/lounge/landing"
    }

    let openapiBaseURL: String
    let tenantCode: String
    let memberShipCode: String
    let saasPublicKey: String
    let customerPrivateKey: String
    let visitorLoginBaseURL: String
    let visitorLoginPath: String
    let loginProductCode: String
    let verifyPurchaseProCode: String
    let language: String
    let channel: String
    let module: String
    let redirectURL: String

    static func bundleDefault() -> DemoDragonPassSSOConfig {
        return DemoDragonPassSSOConfig(
            openapiBaseURL: "https://global-h5-uat.dragonpass.com/api/business/open/interface/request",
            tenantCode: Defaults.tenantCode,
            memberShipCode: Defaults.memberShipCode,
            saasPublicKey: """
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuzMo5tfeIgEpe2XX9KMEZQADgVPIhelVhcbH9rgMQDInFleJvIW4WLJ5zH0RfMezLDN6rEslfAn/AkL/gg6PIPn3NKBF8JvDrr5p3Xai+KVypU42MdlIKa2QxVeI9rVDUb4CpI0OwZEes8w78HL1yQ1/lSwpFUolerw+wsrq3A6/AVpzidNzI92xl7cWF4pO1tSG4g3cnT0Pg6ORJfMgrufCvp3YpZoxvHAwlIEsO1DffMmELQJOzhzbWpHWbXvQ58rDhU5a/vFxAHYW1BxxzBTL+ESV6GO9gLNCN1fXetQusygytf8ozDr4Ec899V90s6hiteDASGF/1YDbBDfPPwIDAQAB
-----END PUBLIC KEY-----
""",
            customerPrivateKey: """
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCcVgDPEjge4faJtZp1KV5XApzR6GgzkJEWY5+a/h2DVXDnFhnsfoM2KyWZZjnWHTo94r4shtuhH/aPV92GpcWo9Yv+jJDX7RbWHZWY9c4I0gn+2Q3D3oO3XKuDnL0dHsEonfJHGEEMcM4FhkLykUfHZOFDMCy+Du6Da2AGceKEmoJOQTVRX5PQE0pbjYk2XeG7fcpYHY1wZFpKb/YOgFwwFmG82vogfS2qrvRPWh+DYXb5gxzsXTLwxDhQX0WOLgzsCRsV3ZEzEh1DBBJyDDAqUxlSV5TkjxSbCML/PvMr+4kODC2zdtoA3MbWBgNOcnBStWXUcmiJy5XxzrbgZUmvAgMBAAECggEADmCOZHytcpGfRZzQ3pN2XJQd7ePsqUlTPnbc97kE584Uuvu6WJht4q5nH8tZ6En50DUo/hlM222AFEClW7ulCNvECx3MOD9SiVBhMJbyYrdGOgymCmxNOrCoCUuBzMrGQsD7xfQCD23UVIe7Ymlf64Nof/BPPQ9MegOG6jDQ/xa9pMHOPnAoyAKlrDCUQVsJthiDSYTPIg3ZJUPJXgA/sh2f2Lf8YW2H8M1Nv4a12ATE15IyQXu1e7NtnFtVpTjMvuAAjUTIt6wpcMCeRos8klYOL4hREdj66JJbIYyka/I6m+wopY/Xb0tMol+OZKha4omEWT3xp3cLUIYjfsGSEQKBgQDU/qwePjdxt8kvcT/Y+tjtDNE5SzOsDAPnzBfuVEN0EnI7RkYvKS0tGNfEY6nxnWCe/nSvJTwIMWwx41kNkyJyoqGdXdYQH7AoS8uHe9mu7ZnYSYRWPmqXOkE4uRKcZdujGTahEJiC4tsjFjv3oOzq2zNfCUdjLIrFT2kVHROzyQKBgQC75rvT6SGgBxGVa+2XATsAyDweHD5Aami4s2YQD8zIwNxuknPI/p8+87x9O7wvJEnzMWxkXKUY7srzXQ5J93VePXq24SGgkrq51+n2P30AgxQ25nvN9FZ+ap9e8/4gdxetSaAMahm4oqBUzRN0B/Zw1AuGUL28X7rFhiyLQWIdtwKBgA7OlZCUqq4RJL9TlCi1Z5czKOhevfzb6PmYSqGa4gWTsrVEMWTd6/ISpA1XEF1nn2vuLJZwdDftl6PwNiSnceGeRLX37AW67jge7MtCZOOwSN2sXrLQLADPX/FdjFmrCxXPjuiriq6urqVFym1wlofNLUkSEBBo7EzDNH7vQothAoGAbIFoU43bugJ69/NURxAR13jJpoWeuSn5gTcvp/THx+H/KObvb9EBeqPbY+Ib4IkvHv2aXzZUrFow3moNN09r+li8RWEqPwScSXdShr3Q3HvVL4LXWW5QiD3f/EAfrvW2uX27q4+VfNaEiZPHOQjkGfGJGi4D8wTA4RGDJYNDOm8CgYAUzRiDZnTGUHdk8k5xH7iceZnvmlm1uaWXTvvJzigzfVrlilMY98Z4mSAGtCUbjUhC0tdmPX73W/4HAjquT0L7A9rz5XTCIa7TfrOi6s5d0PbDKq7dBZSeNzxf4XPxQAPz/Zy9itlaFEtKJmF6JaUHEiXUeUGrf/NF7XZa37zhtA==
-----END PRIVATE KEY-----
""",
            visitorLoginBaseURL: "https://global-h5-uat.dragonpass.com",
            visitorLoginPath: "/api/business/auth/visitor/login",
            loginProductCode: Defaults.loginProductCode,
            verifyPurchaseProCode: Defaults.verifyPurchaseProCode,
            language: Defaults.language,
            channel: Defaults.channel,
            module: Defaults.module,
            redirectURL: Defaults.redirectURL
        )
    }

    fileprivate func openapiBody() -> OpenAPIRequest.PlainBody {
        OpenAPIRequest.PlainBody(
            tenantCode: tenantCode,
            memberShipCode: memberShipCode,
            redirectURL: redirectURL,
            generateShortUrl: true,
            privateKey: "",
            language: language,
            channel: channel,
            productCode: loginProductCode,
            maxPassengerPerOrder: 6,
            pageType: "lounge-landing",
            module: Int(module) ?? 2,
            actionType: "operate",
            thirdInfo: "111111",
            timeZone: "Asia/Seoul"
        )
    }
}

private enum OpenAPIRequest {
    struct EncryptedRequest {
        let headers: [String: String]
        let body: EncryptedBody
    }

    struct EncryptedBody: Encodable {
        let operationCode: String
        let requestId: String
        let version: String
        let encryptKey: String
        let iv: String
        let body: String
    }

    struct PlainBody: Encodable {
        let tenantCode: String
        let memberShipCode: String
        let redirectURL: String
        let generateShortUrl: Bool
        let privateKey: String
        let language: String
        let channel: String
        let productCode: String
        let maxPassengerPerOrder: Int
        let pageType: String
        let module: Int
        let actionType: String
        let thirdInfo: String
        let timeZone: String
    }
}

private enum OpenAPIResponse {
    struct EncryptedBody: Decodable {
        let timestamp: Int
        let nonce: String
        let tenantCode: String
        let encryptKey: String
        let iv: String
        let body: String
        let sign: String
    }

    struct DecryptedBody: Decodable {
        let code: String?
        let msg: String?
        let message: String?
        let data: DataBody?

        private enum CodingKeys: String, CodingKey {
            case code
            case msg
            case message
            case data
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decodeFlexibleStringIfPresent(forKey: .code)
            msg = try container.decodeFlexibleStringIfPresent(forKey: .msg)
            message = try container.decodeFlexibleStringIfPresent(forKey: .message)
            data = try container.decodeIfPresent(DataBody.self, forKey: .data)
        }
    }

    struct DataBody: Decodable {
        let shortUrl: String?
    }
}

private struct VisitorLoginRequest {
    let url: URL
    let body: Body

    struct Body {
        let params: String
        let tenantCode: String
        let productCode: String
        let verifyPurchaseProCode: String?

        var asDictionary: [String: String] {
            var dictionary = [
                "params": params,
                "tenantCode": tenantCode,
                "productCode": productCode
            ]
            if let verifyPurchaseProCode {
                dictionary["verifyPurchaseProCode"] = verifyPurchaseProCode
            }
            return dictionary
        }
    }
}

private enum VisitorLoginResponse {
    struct Body: Decodable {
        let code: String?
        let msg: String?
        let data: DataBody?

        private enum CodingKeys: String, CodingKey {
            case code
            case msg
            case data
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decodeFlexibleStringIfPresent(forKey: .code)
            msg = try container.decodeFlexibleStringIfPresent(forKey: .msg)
            data = try container.decodeIfPresent(DataBody.self, forKey: .data)
        }
    }

    struct DataBody: Decodable {
        let token: String?
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

private struct ASN1Reader {
    private let data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readConstructed(tag: UInt8) throws -> ASN1Reader {
        try ASN1Reader(data: readTLV(tag: tag))
    }

    mutating func readPrimitive(tag: UInt8) throws -> Data {
        try readTLV(tag: tag)
    }

    private mutating func readTLV(tag expectedTag: UInt8) throws -> Data {
        guard offset < data.count else {
            throw DemoLoginAPIError.decoding("ASN.1 data ended unexpectedly")
        }
        let tag = data[offset]
        offset += 1
        guard tag == expectedTag else {
            throw DemoLoginAPIError.decoding("Unexpected ASN.1 tag")
        }

        let length = try readLength()
        guard offset + length <= data.count else {
            throw DemoLoginAPIError.decoding("ASN.1 length exceeds data")
        }

        let start = offset
        offset += length
        return data.subdata(in: start..<offset)
    }

    private mutating func readLength() throws -> Int {
        guard offset < data.count else {
            throw DemoLoginAPIError.decoding("Missing ASN.1 length")
        }

        let first = data[offset]
        offset += 1

        if first & 0x80 == 0 {
            return Int(first)
        }

        let byteCount = Int(first & 0x7f)
        guard byteCount > 0, byteCount <= 4, offset + byteCount <= data.count else {
            throw DemoLoginAPIError.decoding("Invalid ASN.1 length")
        }

        var length = 0
        for _ in 0..<byteCount {
            length = (length << 8) | Int(data[offset])
            offset += 1
        }
        return length
    }
}

private enum Crypto {
    static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw DemoLoginAPIError.server(code: "RANDOM_FAILED", message: "Failed to generate random bytes")
        }
        return Data(bytes)
    }

    static func encryptAES(plainText: String, keyBase64: String, ivBase64: String) throws -> String {
        try cryptAES(data: Data(plainText.utf8), keyBase64: keyBase64, ivBase64: ivBase64, operation: CCOperation(kCCEncrypt)).base64EncodedString()
    }

    static func decryptAES(cipherTextBase64: String, keyBase64: String, ivBase64: String) throws -> String {
        guard let cipherData = Data(base64Encoded: cipherTextBase64) else {
            throw DemoLoginAPIError.decoding("Invalid AES cipher text")
        }
        let plainData = try cryptAES(data: cipherData, keyBase64: keyBase64, ivBase64: ivBase64, operation: CCOperation(kCCDecrypt))
        guard let text = String(data: plainData, encoding: .utf8) else {
            throw DemoLoginAPIError.decoding("AES decrypted data is not UTF-8")
        }
        return text
    }

    static func encryptRSA(plainText: String, publicKeyPEM: String) throws -> String {
        let key = try makeRSAKey(pem: publicKeyPEM, keyClass: kSecAttrKeyClassPublic)
        let data = Data(plainText.utf8)
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, data as CFData, &error) as Data? else {
            throw cryptoError(error, fallback: .server(code: "RSA_ENCRYPT_FAILED", message: "RSA public encrypt failed"))
        }
        return encrypted.base64EncodedString()
    }

    static func decryptRSA(cipherTextBase64: String, privateKeyPEM: String) throws -> String {
        guard let cipherData = Data(base64Encoded: cipherTextBase64) else {
            throw DemoLoginAPIError.decoding("Invalid RSA cipher text")
        }
        let key = try makeRSAKey(pem: privateKeyPEM, keyClass: kSecAttrKeyClassPrivate)
        var error: Unmanaged<CFError>?
        guard let decrypted = SecKeyCreateDecryptedData(key, .rsaEncryptionPKCS1, cipherData as CFData, &error) as Data? else {
            throw cryptoError(error, fallback: .server(code: "RSA_DECRYPT_FAILED", message: "RSA private decrypt failed"))
        }
        return try normalizeAESKeyMaterial(decrypted)
    }

    static func signSHA256RSA(_ content: String, privateKeyPEM: String) throws -> String {
        let key = try makeRSAKey(pem: privateKeyPEM, keyClass: kSecAttrKeyClassPrivate)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(content.utf8) as CFData, &error) as Data? else {
            throw cryptoError(error, fallback: .server(code: "RSA_SIGN_FAILED", message: "RSA sign failed"))
        }
        return signature.base64EncodedString()
    }

    static func verifySHA256RSA(_ content: String, signatureBase64: String, publicKeyPEM: String) throws -> Bool {
        guard let signature = Data(base64Encoded: signatureBase64) else {
            throw DemoLoginAPIError.decoding("Invalid RSA signature")
        }
        let key = try makeRSAKey(pem: publicKeyPEM, keyClass: kSecAttrKeyClassPublic)
        var error: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(content.utf8) as CFData, signature as CFData, &error)
        if let error {
            throw error.takeRetainedValue()
        }
        return ok
    }

    private static func cryptAES(data: Data, keyBase64: String, ivBase64: String, operation: CCOperation) throws -> Data {
        guard let key = Data(base64Encoded: keyBase64), let iv = Data(base64Encoded: ivBase64) else {
            throw DemoLoginAPIError.decoding("Invalid AES key or IV")
        }

        var output = Data(count: data.count + kCCBlockSizeAES128)
        var outputLength = 0
        let outputCapacity = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw DemoLoginAPIError.server(code: "AES_CRYPT_FAILED", message: "AES operation failed: \(status)")
        }

        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private static func makeRSAKey(pem: String, keyClass: CFString) throws -> SecKey {
        let der = try rsaKeyDER(from: pem, keyClass: keyClass)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: keyClass
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            throw cryptoError(error, fallback: .server(code: "RSA_KEY_INVALID", message: "Invalid RSA key"))
        }
        return key
    }

    private static func cryptoError(_ error: Unmanaged<CFError>?, fallback: DemoLoginAPIError) -> Error {
        error?.takeRetainedValue() ?? fallback
    }

    private static func rsaKeyDER(from pem: String, keyClass: CFString) throws -> Data {
        let normalizedPEM = pem.replacingOccurrences(of: "\\n", with: "\n")
        let der = try decodePEM(normalizedPEM)

        if keyClass == kSecAttrKeyClassPrivate,
           normalizedPEM.contains("BEGIN PRIVATE KEY"),
           !normalizedPEM.contains("BEGIN RSA PRIVATE KEY") {
            return try unwrapPKCS8PrivateKey(der)
        }

        if keyClass == kSecAttrKeyClassPublic,
           normalizedPEM.contains("BEGIN PUBLIC KEY"),
           !normalizedPEM.contains("BEGIN RSA PUBLIC KEY") {
            return try unwrapSubjectPublicKeyInfo(der)
        }

        return der
    }

    private static func decodePEM(_ pem: String) throws -> Data {
        let base64 = pem
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("-----") }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !base64.isEmpty, let data = Data(base64Encoded: base64) else {
            throw DemoLoginAPIError.server(code: "RSA_KEY_MISSING", message: "RSA key is missing or invalid")
        }
        return data
    }

    private static func unwrapPKCS8PrivateKey(_ der: Data) throws -> Data {
        do {
            var reader = ASN1Reader(data: der)
            var sequence = try reader.readConstructed(tag: 0x30)
            _ = try sequence.readPrimitive(tag: 0x02)
            _ = try sequence.readConstructed(tag: 0x30)
            return try sequence.readPrimitive(tag: 0x04)
        } catch {
            throw DemoLoginAPIError.server(code: "RSA_KEY_INVALID", message: "Invalid PKCS#8 RSA private key")
        }
    }

    private static func unwrapSubjectPublicKeyInfo(_ der: Data) throws -> Data {
        do {
            var reader = ASN1Reader(data: der)
            var sequence = try reader.readConstructed(tag: 0x30)
            _ = try sequence.readConstructed(tag: 0x30)
            let bitString = try sequence.readPrimitive(tag: 0x03)
            guard bitString.first == 0x00 else {
                throw DemoLoginAPIError.server(code: "RSA_KEY_INVALID", message: "Invalid RSA public key bit string")
            }
            return Data(bitString.dropFirst())
        } catch {
            throw DemoLoginAPIError.server(code: "RSA_KEY_INVALID", message: "Invalid X.509 RSA public key")
        }
    }

    private static func normalizeAESKeyMaterial(_ data: Data) throws -> String {
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let decoded = Data(base64Encoded: text), [16, 24, 32].contains(decoded.count) {
            return text
        }
        if [16, 24, 32].contains(data.count) {
            return data.base64EncodedString()
        }
        if let textData = text.data(using: .utf8), [16, 24, 32].contains(textData.count) {
            return textData.base64EncodedString()
        }
        throw DemoLoginAPIError.server(code: "AES_KEY_INVALID", message: "Unsupported AES key material length")
    }
}
