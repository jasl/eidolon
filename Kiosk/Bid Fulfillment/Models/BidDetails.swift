import UIKit
import RxSwift
import MoyaX

@objc class BidDetails: NSObject {
    typealias DownloadImageClosure = (url: NSURL, imageView: UIImageView) -> ()

    let auctionID: String

    var newUser: NewUser = NewUser()
    var saleArtwork: SaleArtwork?

    var paddleNumber = Variable<String?>(nil)
    var bidderPIN = Variable<String?>(nil)
    var bidAmountCents = Variable<NSNumber?>(nil)
    var bidderID = Variable<String?>(nil)

    var setImage: DownloadImageClosure = { (url, imageView) -> () in
        imageView.sd_setImageWithURL(url)
    }

    init(saleArtwork: SaleArtwork?, paddleNumber: String?, bidderPIN: String?, bidAmountCents: Int?, auctionID: String) {
        self.auctionID = auctionID
        self.saleArtwork = saleArtwork
        self.paddleNumber.value = paddleNumber
        self.bidderPIN.value = bidderPIN
        self.bidAmountCents.value = bidAmountCents
    }

    /// Creates a new authenticated networking provider based on either:
    /// - User's paddle/phone # and PIN, or
    /// - User's email and password
    func authenticatedNetworking(provider: Networking) -> Observable<AuthorizedNetworking> {

        let auctionID = saleArtwork?.auctionID ?? ""

        if let number = paddleNumber.value, let pin = bidderPIN.value {
            let newWillTransformToRequestClosure: Endpoint -> Endpoint = { endpoint in
                // Grab existing endpoint to piggy-back off of any existing configurations being used by the sharedprovider.
                var endpoint = Networking.willTransformToRequestClosure()(endpoint: endpoint)

                endpoint.headerFields["auction_pin"] = pin
                endpoint.headerFields["number"] = number
                endpoint.headerFields["sale_id"] = auctionID

                return endpoint
            }

            let provider = OnlineProvider<ArtsyAuthenticatedAPI>(backend: Networking.APIKeysBasedBackend(), plugins: Networking.authenticatedPlugins, willTransformToRequest: newWillTransformToRequestClosure)

            return .just(AuthorizedNetworking(provider: provider))

        } else {
            let endpoint: ArtsyAPI = ArtsyAPI.XAuth(email: newUser.email.value ?? "", password: newUser.password.value ?? "")

            return provider.request(endpoint)
                .filterSuccessfulStatusCodes()
                .mapJSON()
                .flatMap { accessTokenDict -> Observable<AuthorizedNetworking> in
                    guard let accessToken = accessTokenDict["access_token"] as? String else {
                        return Observable.error(EidolonError.CouldNotParseJSON)
                    }

                    return .just(Networking.newAuthorizedNetworking(accessToken))
                }
                .logServerError("Getting Access Token failed.")
        }
    }
}
