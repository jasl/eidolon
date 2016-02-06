import UIKit
import ECPhoneNumberFormatter
import MoyaX
import RxSwift
import Action

class ConfirmYourBidViewController: UIViewController {

    private var _number = Variable("")
    let phoneNumberFormatter = ECPhoneNumberFormatter()

    @IBOutlet var bidDetailsPreviewView: BidDetailsPreviewView!
    @IBOutlet var numberAmountTextField: TextField!
    @IBOutlet var cursor: CursorView!
    @IBOutlet var keypadContainer: KeypadContainerView!
    @IBOutlet var enterButton: UIButton!
    @IBOutlet var useArtsyLoginButton: UIButton!

    private let _viewWillDisappear = PublishSubject<Void>()
    var viewWillDisappear: Observable<Void> {
        return self._viewWillDisappear.asObserver()
    }

    // Need takeUntil because we bind this observable eventually to bidDetails, making us stick around longer than we should!
    lazy var number: Observable<String> = { self.keypadContainer.stringValue.takeUntil(self.viewWillDisappear) }()

    var provider: Networking!

    class func instantiateFromStoryboard(storyboard: UIStoryboard) -> ConfirmYourBidViewController {
        return storyboard.viewControllerWithID(.ConfirmYourBid) as! ConfirmYourBidViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleString = useArtsyLoginButton.titleForState(useArtsyLoginButton.state)! ?? ""
        let attributes = [NSUnderlineStyleAttributeName: NSUnderlineStyle.StyleSingle.rawValue,
            NSFontAttributeName: useArtsyLoginButton.titleLabel!.font];
        let attrTitle = NSAttributedString(string: titleString, attributes:attributes)
        useArtsyLoginButton.setAttributedTitle(attrTitle, forState:useArtsyLoginButton.state)

        number
            .bindTo(_number)
            .addDisposableTo(rx_disposeBag)

        number
            .map(toPhoneNumberString)
            .bindTo(numberAmountTextField.rx_text)
            .addDisposableTo(rx_disposeBag)

        let nav = self.fulfillmentNav()

        let optionalNumber = number.mapToOptional()

        // We don't know if it's a paddle number or a phone number yet, so bind both ¯\_(ツ)_/¯
        [nav.bidDetails.paddleNumber, nav.bidDetails.newUser.phoneNumber].forEach { variable in
            optionalNumber
                .bindTo(variable)
                .addDisposableTo(rx_disposeBag)
        }

        // Does a bidder exist for this phone number?
        //   if so forward to PIN input VC
        //   else send to enter email

        let auctionID = nav.auctionID

        let numberIsZeroLength = number.map(isZeroLengthString)

        enterButton.rx_action = CocoaAction(enabledIf: numberIsZeroLength.not(), workFactory: { [weak self] _ in
            guard let me = self else { return .empty() }

            let endpoint = ArtsyAPI.FindBidderRegistration(auctionID: auctionID, phone: String(me._number.value))

            return me.provider.request(endpoint)
                .filterStatusCode(400)
                .map(void)
                .doOnError { error in
                    guard let me = self else { return }

                    // Due to AlamoFire restrictions we can't stop HTTP redirects
                    // so to figure out if we got 302'd we have to introspect the
                    // error to see if it's the original URL to know if the
                    // request succeeded.

                    var response: MoyaX.Response?

                    if case .StatusCode(let receivedResponse)? = error as? MoyaX.Error {
                        response = receivedResponse
                    }

                    if let responseURL = response?.response?.URL?.absoluteString
                        where responseURL.containsString("v1/bidder/") {

                        me.performSegue(.ConfirmyourBidBidderFound)
                    } else {
                        me.performSegue(.ConfirmyourBidBidderNotFound)
                    }
                }

        })
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        _viewWillDisappear.onNext()
    }

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue == .ConfirmyourBidBidderFound {
            let nextViewController = segue.destinationViewController as! ConfirmYourBidPINViewController
            nextViewController.provider = provider
        } else if segue == .ConfirmyourBidBidderNotFound {
            let viewController = segue.destinationViewController as! ConfirmYourBidEnterYourEmailViewController
            viewController.provider = provider
        } else if segue == .ConfirmyourBidArtsyLogin {
            let viewController = segue.destinationViewController as! ConfirmYourBidArtsyLoginViewController
            viewController.provider = provider
        } else if segue == .ConfirmyourBidBidderFound {
            let viewController = segue.destinationViewController as! ConfirmYourBidPINViewController
            viewController.provider = provider
        }
    }

    func toOpeningBidString(cents:AnyObject!) -> AnyObject! {
        if let dollars = NSNumberFormatter.currencyStringForCents(cents as? Int) {
            return "Enter \(dollars) or more"
        }
        return ""
    }

    func toPhoneNumberString(number: String) -> String {
        if number.characters.count >= 7 {
            return phoneNumberFormatter.stringForObjectValue(number) ?? number
        } else {
            return number
        }
    }
}

private extension ConfirmYourBidViewController {


    @IBAction func dev_noPhoneNumberFoundTapped(sender: AnyObject) {
        self.performSegue(.ConfirmyourBidArtsyLogin )
    }

    @IBAction func dev_phoneNumberFoundTapped(sender: AnyObject) {
        self.performSegue(.ConfirmyourBidBidderFound)
    }

}
