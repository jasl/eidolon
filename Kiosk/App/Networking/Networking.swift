import Foundation
import ISO8601DateFormatter
import MoyaX
import RxSwift
import Result

class OnlineProvider<Target where Target: TargetType>: RxMoyaXProvider<Target> {

    private let online: Observable<Bool>

    init(backend: BackendType = AlamofireBackend(),
         plugins: [PluginType] = [],
         willTransformToRequest: (Endpoint -> Endpoint)? = nil,
         online: Observable<Bool> = connectedToInternetOrStubbing()) {

            self.online = online
            super.init(backend: backend, plugins: plugins, willTransformToRequest: willTransformToRequest)
    }

    override func request(token: Target) -> Observable<MoyaX.Response> {
        let actualRequest = super.request(token)
        return online
            .ignore(false)  // Wait until we're online
            .take(1)        // Take 1 to make sure we only invoke the API once.
            .flatMap { _ in // Turn the online state into a network request
                return actualRequest
            }
    }
}

class RequestResolverPlugin: PluginType {
    func willSendRequest(request: NSMutableURLRequest, target: TargetType) {
        request.HTTPShouldHandleCookies = false
    }

    func didReceiveResponse(result: Result<MoyaX.Response, MoyaX.Error>, target: TargetType) {}
}

protocol NetworkingType {
    typealias T: TargetType, ArtsyAPIType
    var provider: OnlineProvider<T> { get }
}

struct Networking: NetworkingType {
    typealias T = ArtsyAPI
    let provider: OnlineProvider<ArtsyAPI>
}

struct AuthorizedNetworking: NetworkingType {
    typealias T = ArtsyAuthenticatedAPI
    let provider: OnlineProvider<ArtsyAuthenticatedAPI>
}

private extension Networking {

    /// Request to fetch and store new XApp token if the current token is missing or expired.
    func XAppTokenRequest(defaults: NSUserDefaults) -> Observable<String?> {

        var appToken = XAppToken(defaults: defaults)

        // If we have a valid token, return it and forgo a request for a fresh one.
        if appToken.isValid {
            return Observable.just(appToken.token)
        }

        let newTokenRequest = self.provider.request(ArtsyAPI.XApp)
            .filterSuccessfulStatusCodes()
            .mapJSON()
            .map { element -> (token: String?, expiry: String?) in
                guard let dictionary = element as? NSDictionary else { return (token: nil, expiry: nil) }

                return (token: dictionary["xapp_token"] as? String, expiry: dictionary["expires_in"] as? String)
            }
            .doOn { event in
                guard case Event.Next(let element) = event else { return }

                let formatter = ISO8601DateFormatter()
                // These two lines set the defaults values injected into appToken
                appToken.token = element.0
                appToken.expiry = formatter.dateFromString(element.1)
            }
            .map { (token, expiry) -> String? in
                return token
            }
            .logError()

        return newTokenRequest
    }
}

// "Public" interfaces
extension Networking {
    /// Request to fetch a given target. Ensures that valid XApp tokens exist before making request
    func request(token: ArtsyAPI, defaults: NSUserDefaults = NSUserDefaults.standardUserDefaults()) -> Observable<MoyaX.Response> {

        let actualRequest = self.provider.request(token)
        return self.XAppTokenRequest(defaults).flatMap { _ in actualRequest }
    }
}

extension AuthorizedNetworking {
    func request(token: ArtsyAuthenticatedAPI, defaults: NSUserDefaults = NSUserDefaults.standardUserDefaults()) -> Observable<MoyaX.Response> {
        return self.provider.request(token)
    }
}

// Static methods
extension NetworkingType {

    static func newDefaultNetworking() -> Networking {
        return Networking(provider: newProvider(plugins))
    }

    static func newAuthorizedNetworking(xAccessToken: String) -> AuthorizedNetworking {
        return AuthorizedNetworking(provider: newProvider(authenticatedPlugins, xAccessToken: xAccessToken))
    }

    static func newStubbingNetworking() -> Networking {
        return Networking(provider: OnlineProvider(backend: StubBackend(), plugins: [RequestResolverPlugin()], willTransformToRequest: willTransformToRequestClosure(), online: .just(true)))
    }

    static func newAuthorizedStubbingNetworking() -> AuthorizedNetworking {
        return AuthorizedNetworking(provider: OnlineProvider(backend: StubBackend(), plugins: [RequestResolverPlugin()], willTransformToRequest: willTransformToRequestClosure(), online: .just(true)))
    }

    static func willTransformToRequestClosure(xAccessToken: String? = nil)(var endpoint: Endpoint) -> Endpoint {
        // If we were given an xAccessToken, add it
        if let xAccessToken = xAccessToken {
            endpoint.headerFields["X-Access-Token"] = xAccessToken
        }

        return endpoint
    }

    static func APIKeysBasedBackend() -> BackendType {
        if APIKeys.sharedKeys.stubResponses {
            return StubBackend()
        } else {
            return AlamofireBackend()
        }
    }

    static var plugins: [PluginType] {
        return [
            NetworkLogger(blacklist: { target -> Bool in
                guard let target = target as? ArtsyAPI else { return false }

                switch target {
                case .Ping: return true
                default: return false
                }
            }), RequestResolverPlugin()
        ]
    }

    static var authenticatedPlugins: [PluginType] {
        return [
            NetworkLogger(whitelist: { target -> Bool in
                guard let target = target as? ArtsyAuthenticatedAPI else { return false }

                switch target {
                case .MyBidPosition: return true
                default: return false
                }
            }), RequestResolverPlugin()
        ]
    }
}

private func newProvider<T where T: TargetType, T: ArtsyAPIType>(plugins: [PluginType], xAccessToken: String? = nil) -> OnlineProvider<T> {
    return OnlineProvider(backend: Networking.APIKeysBasedBackend(), plugins: plugins, willTransformToRequest: Networking.willTransformToRequestClosure(xAccessToken))
}
